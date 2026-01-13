# MCP Client Configuration Guide

ZEMACS is designed to work with any Model Context Protocol (MCP) compatible editor or agent. Below are the configurations for popular clients.

## 1. Claude Desktop (Anthropic)
**Config Path**:
- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Linux: `~/.config/Claude/claude_desktop_config.json` (or similar)

**Configuration**:
```json
{
  "mcpServers": {
    "zemacs": {
      "command": "/absolute/path/to/zemacs/zig-out/bin/zemacs",
      "args": []
    }
  }
}
```

## 2. Windsurf (Codeium)
**Config Path**: `~/.codeium/windsurf/mcp_config.json`

**Configuration**:
```json
{
  "mcpServers": {
    "zemacs": {
      "command": "/absolute/path/to/zemacs/zig-out/bin/zemacs",
      "args": []
    }
  }
}
```

## 3. Cursor
Cursor currently supports MCP via extension or experimental settings. 
Use the generic MCP server setup:
- **Transport**: Stdio
- **Command**: `/absolute/path/to/zemacs/zig-out/bin/zemacs`

## 4. Emacs (Native Client)
Add `zemacs-client.el` to your configuration.

**Multi-Agent Setup (TCP)**:
Ideally, you run ZEMACS as a persistent background service (e.g., systemd) and have all clients connect via TCP.

**Start Server**:
```bash
/path/to/zemacs -mode tcp -port 3000
```

**Emacs Config**:
```elisp
(require 'zemacs-client)
(setq zemacs-connection-type 'tcp)
(setq zemacs-tcp-port 3000)
(zemacs-connect)
```
*(Note: Ensure your `zemacs-client.el` supports TCP connections)*
