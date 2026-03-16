"""CLI entry points for jasketch-mcp-server and jasketch-relay."""

import os
import subprocess
import sys


def _run_jac(filename):
    """Run a .jac file from this package directory."""
    jac_file = os.path.join(os.path.dirname(__file__), filename)
    subprocess.run([sys.executable, "-m", "jaclang", "run", jac_file], check=True)


def run_server():
    """Run the JaSketch MCP server."""
    _run_jac("server.jac")


def run_relay():
    """Run the JaSketch WebSocket relay."""
    _run_jac("relay.jac")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "relay":
        run_relay()
    else:
        run_server()


if __name__ == "__main__":
    main()
