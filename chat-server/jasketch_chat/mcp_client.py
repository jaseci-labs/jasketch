"""MCP Client Manager - spawns jasketch-mcp-server and communicates via stdio."""

import json
import logging
import os
import shutil
from contextlib import AsyncExitStack

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

logger = logging.getLogger(__name__)


def _mcp_tool_to_openai(tool) -> dict:
    """Convert an MCP tool definition to OpenAI function-calling format."""
    schema = tool.inputSchema if hasattr(tool, "inputSchema") else {}
    return {
        "type": "function",
        "function": {
            "name": tool.name,
            "description": tool.description or "",
            "parameters": schema,
        },
    }


class MCPClientManager:
    """Manages a jasketch-mcp-server subprocess and provides tool access."""

    def __init__(self) -> None:
        self._session: ClientSession | None = None
        self._exit_stack: AsyncExitStack | None = None
        self._tools_cache: list[dict] | None = None

    async def start(self) -> None:
        """Spawn the MCP server subprocess and initialize the session."""
        command = self._find_server_command()
        logger.info("Starting MCP server subprocess: %s", command)

        # Pass env so MCP server starts its embedded local relay
        # instead of connecting to the remote one
        relay_port = os.environ.get("JASKETCH_RELAY_PORT", "9601")
        env = {
            **os.environ,
            "JASKETCH_RELAY_URL": f"ws://localhost:{relay_port}",
            "JASKETCH_RELAY_PORT": relay_port,
        }

        server_params = StdioServerParameters(
            command=command,
            args=[],
            env=env,
        )

        self._exit_stack = AsyncExitStack()
        stdio_transport = await self._exit_stack.enter_async_context(
            stdio_client(server_params)
        )
        read_stream, write_stream = stdio_transport
        self._session = await self._exit_stack.enter_async_context(
            ClientSession(read_stream, write_stream)
        )

        await self._session.initialize()

        # Discover and cache tools
        tools_result = await self._session.list_tools()
        self._tools_cache = [_mcp_tool_to_openai(t) for t in tools_result.tools]
        logger.info(
            "MCP session ready — discovered %d tools: %s",
            len(self._tools_cache),
            [t["function"]["name"] for t in self._tools_cache],
        )

    async def stop(self) -> None:
        """Close the session and kill the subprocess."""
        if self._exit_stack:
            await self._exit_stack.aclose()
            self._exit_stack = None
        self._session = None
        self._tools_cache = None
        logger.info("MCP client stopped")

    def get_tools(self) -> list[dict]:
        """Return tool definitions in OpenAI function-calling format."""
        if self._tools_cache is None:
            raise RuntimeError("MCP client not started — call start() first")
        return self._tools_cache

    async def call_tool(self, name: str, arguments: dict) -> dict:
        """Execute a tool on the MCP server and return the result."""
        if self._session is None:
            raise RuntimeError("MCP client not started — call start() first")

        logger.info("Calling MCP tool: %s(%s)", name, json.dumps(arguments)[:200])
        result = await self._session.call_tool(name, arguments)

        # Extract text content from MCP result
        text_parts = []
        for content in result.content:
            if hasattr(content, "text"):
                text_parts.append(content.text)

        combined = "\n".join(text_parts)
        try:
            return json.loads(combined)
        except (json.JSONDecodeError, ValueError):
            return {"result": combined}

    def _find_server_command(self) -> str:
        """Find the jasketch-mcp-server executable."""
        cmd = shutil.which("jasketch-mcp-server")
        if cmd:
            return cmd
        raise RuntimeError(
            "Cannot find jasketch-mcp-server. "
            "Install it with: pip install jasketch-mcp-server"
        )
