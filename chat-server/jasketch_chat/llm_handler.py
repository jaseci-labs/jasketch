"""LLM handler - streams completions and executes MCP tool calls."""

import json
import logging
from collections.abc import AsyncGenerator

import litellm

from .mcp_client import MCPClientManager

logger = logging.getLogger(__name__)

MAX_TOOL_ITERATIONS = 10

SYSTEM_PROMPT = (
    "You are a whiteboard AI assistant for JaSketch. You can create and manipulate "
    "elements on the canvas using the provided tools.\n\n"
    "Available element types: rectangle, circle, diamond, line, arrow, text, freehand.\n\n"
    "Guidelines:\n"
    "- Use x, y for shape/text position and x1, y1, x2, y2 for lines/arrows.\n"
    "- Shapes have width/height. Default size is 100x100 if not specified.\n"
    "- Use create_elements for batch creation (more efficient for diagrams).\n"
    "- Use get_canvas_snapshot to visually verify your work after making changes.\n"
    "- Use get_bounding_box to find free space before adding elements.\n"
    "- Colors are hex strings like '#ff0000'. Default is '#000000'.\n"
    "- fillColor controls shape fill. Use 'transparent' for no fill.\n"
    "- Shapes can have text via shapeText, shapeTextColor, shapeTextFontSize.\n"
    "- For arrows/lines, use bendX/bendY to create curved connections.\n"
)


async def chat_completion_stream(
    messages: list[dict],
    api_key: str,
    model: str,
    mcp_manager: MCPClientManager,
) -> AsyncGenerator[dict, None]:
    """Stream LLM completion with MCP tool execution, yielding SSE events."""

    tools = mcp_manager.get_tools()

    # Prepend system prompt if not already present
    if not messages or messages[0].get("role") != "system":
        messages = [{"role": "system", "content": SYSTEM_PROMPT}] + messages

    iteration = 0
    while iteration < MAX_TOOL_ITERATIONS:
        iteration += 1

        try:
            response = await litellm.acompletion(
                model=model,
                messages=messages,
                tools=tools if tools else None,
                api_key=api_key,
                stream=True,
            )
        except Exception as e:
            logger.error("LLM API error: %s", e)
            yield {"event": "error", "data": json.dumps({"message": str(e)})}
            return

        # Accumulate streamed response
        content_parts: list[str] = []
        tool_calls_acc: dict[int, dict] = {}
        finish_reason = None

        try:
            async for chunk in response:
                delta = chunk.choices[0].delta if chunk.choices else None
                if delta is None:
                    continue

                # Stream content deltas
                if delta.content:
                    content_parts.append(delta.content)
                    yield {
                        "event": "content_delta",
                        "data": json.dumps({"content": delta.content}),
                    }

                # Accumulate tool calls from streamed chunks
                if delta.tool_calls:
                    for tc in delta.tool_calls:
                        idx = tc.index
                        if idx not in tool_calls_acc:
                            tool_calls_acc[idx] = {
                                "id": tc.id or "",
                                "name": "",
                                "arguments": "",
                            }
                        if tc.id:
                            tool_calls_acc[idx]["id"] = tc.id
                        if tc.function:
                            if tc.function.name:
                                tool_calls_acc[idx]["name"] = tc.function.name
                            if tc.function.arguments:
                                tool_calls_acc[idx]["arguments"] += (
                                    tc.function.arguments
                                )

                if chunk.choices[0].finish_reason:
                    finish_reason = chunk.choices[0].finish_reason
        except Exception as e:
            logger.error("Stream error: %s", e)
            yield {"event": "error", "data": json.dumps({"message": str(e)})}
            return

        # If no tool calls, we're done
        if finish_reason != "tool_calls" or not tool_calls_acc:
            yield {"event": "done", "data": "{}"}
            return

        # Build assistant message with tool calls for conversation history
        full_content = "".join(content_parts) or None
        assistant_tool_calls = []
        for idx in sorted(tool_calls_acc.keys()):
            tc = tool_calls_acc[idx]
            assistant_tool_calls.append({
                "id": tc["id"],
                "type": "function",
                "function": {
                    "name": tc["name"],
                    "arguments": tc["arguments"],
                },
            })

        messages.append({
            "role": "assistant",
            "content": full_content,
            "tool_calls": assistant_tool_calls,
        })

        # Execute each tool call
        for tc_msg in assistant_tool_calls:
            tool_name = tc_msg["function"]["name"]
            tool_call_id = tc_msg["id"]
            try:
                arguments = json.loads(tc_msg["function"]["arguments"])
            except json.JSONDecodeError:
                arguments = {}

            yield {
                "event": "tool_call",
                "data": json.dumps({
                    "name": tool_name,
                    "arguments": arguments,
                }),
            }

            # Execute via MCP
            try:
                result = await mcp_manager.call_tool(tool_name, arguments)
            except Exception as e:
                logger.error("Tool execution error: %s — %s", tool_name, e)
                result = {"error": str(e)}

            yield {
                "event": "tool_result",
                "data": json.dumps({
                    "name": tool_name,
                    "result": result,
                }),
            }

            # Add tool result to conversation for next LLM call
            # Truncate snapshot data to avoid blowing up context
            result_str = json.dumps(result)
            if len(result_str) > 5000 and tool_name == "get_canvas_snapshot":
                result_str = json.dumps({
                    "snapshot": "[base64 image captured successfully]"
                })

            messages.append({
                "role": "tool",
                "tool_call_id": tool_call_id,
                "content": result_str,
            })

        # Loop back to call LLM again with tool results

    # Exceeded max iterations
    yield {
        "event": "error",
        "data": json.dumps({
            "message": f"Exceeded maximum tool iterations ({MAX_TOOL_ITERATIONS})"
        }),
    }
