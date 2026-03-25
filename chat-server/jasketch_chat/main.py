"""FastAPI chat server for JaSketch — proxies LLM calls with MCP tool execution."""

import logging
import os
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse

from .llm_handler import chat_completion_stream
from .mcp_client import MCPClientManager

logger = logging.getLogger(__name__)
logging.basicConfig(
    level=logging.INFO,
    format="[jasketch-chat] %(message)s",
)

CHAT_PORT = int(os.environ.get("CHAT_SERVER_PORT", "8001"))
CHAT_HOST = os.environ.get("CHAT_SERVER_HOST", "0.0.0.0")

mcp_manager = MCPClientManager()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Start MCP server subprocess on startup, stop on shutdown."""
    await mcp_manager.start()
    yield
    await mcp_manager.stop()


app = FastAPI(title="JaSketch Chat", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ChatRequest(BaseModel):
    messages: list[dict]
    api_key: str
    model: str = "gpt-4o"


@app.post("/chat/completions")
async def chat_completions(request: ChatRequest):
    """Stream an LLM completion with MCP tool execution via SSE."""

    async def event_generator():
        async for event in chat_completion_stream(
            messages=request.messages,
            api_key=request.api_key,
            model=request.model,
            mcp_manager=mcp_manager,
        ):
            yield event

    return EventSourceResponse(event_generator())


@app.get("/health")
async def health():
    """Health check endpoint."""
    tools = []
    try:
        tools = [t["function"]["name"] for t in mcp_manager.get_tools()]
    except RuntimeError:
        pass
    return {"status": "ok", "tools": tools}


def run():
    """CLI entry point."""
    uvicorn.run(
        "jasketch_chat.main:app",
        host=CHAT_HOST,
        port=CHAT_PORT,
        log_level="info",
    )


if __name__ == "__main__":
    run()
