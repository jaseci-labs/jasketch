"""CLI entry points for jasketch-mcp-server and jasketch-relay."""

import os
import sys


def run_server():
    """Run the JaSketch MCP server."""
    from jaclang import jac_import

    jac_import("server", base_path=os.path.dirname(__file__))


def run_relay():
    """Run the JaSketch WebSocket relay."""
    from jaclang import jac_import

    jac_import("relay", base_path=os.path.dirname(__file__))


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "relay":
        run_relay()
    else:
        run_server()


if __name__ == "__main__":
    main()
