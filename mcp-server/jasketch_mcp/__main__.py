"""CLI entry points for jasketch-mcp-server."""

import os
import subprocess
import sys


def _run_jac(filename):
    """Run a .jac file from this package directory."""
    jac_file = os.path.join(os.path.dirname(__file__), filename)
    subprocess.run([sys.executable, "-m", "jaclang", "run", jac_file], check=True)


def run_server():
    """Run the JaSketch MCP server (stdio transport)."""
    os.environ.setdefault("JASKETCH_MCP_TRANSPORT", "stdio")
    _run_jac("server.jac")


def run_server_http():
    """Run the JaSketch MCP server (streamable-http transport)."""
    os.environ["JASKETCH_MCP_TRANSPORT"] = "streamable-http"
    _run_jac("server.jac")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "http":
        run_server_http()
    else:
        run_server()


if __name__ == "__main__":
    main()
