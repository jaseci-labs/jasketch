# jasketch-mcp-server

MCP server for [JaSketch](https://jasketch.jaseci.org). Lets an AI assistant draw
on a JaSketch canvas you have open in a browser.

```bash
claude mcp add --scope user jasketch -- uvx jasketch-mcp-server@latest
```

Set `JASKETCH_SESSION_ID` to the tab you want to draw on: run
`sessionStorage.getItem('jasketch_session_id')` in that tab's devtools console.

| Variable | Default | Description |
|----------|---------|-------------|
| `JASKETCH_RELAY_URL` | `wss://jasketch.jaseci.org/ws/function/jasketch_relay` | The app's relay endpoint |
| `JASKETCH_SESSION_ID` | - | Which browser tab to draw on (required) |
| `JASKETCH_MCP_TRANSPORT` | `stdio` | `stdio` or `streamable-http` |
| `JASKETCH_MCP_PORT` | `3003` | Port, when transport is `streamable-http` |
| `JASKETCH_MCP_HOST` | `0.0.0.0` | Bind address, when transport is `streamable-http` |

Source lives in the [JaSketch repo](https://github.com/jaseci-labs/jasketch)
under `mcp_server/`. It is written in Jac; the published wheel is transpiled
Python with a vendored jac runtime, so it needs no jac toolchain to run.
