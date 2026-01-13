# ZEMACS: The Agentic MCP Server

**ZEMACS** is a high-performance **Model Context Protocol (MCP)** server built in **Zig**. It is designed to act as a backend for autonomous coding agents, enabling Emacs (and other clients) to become powerful agentic IDEs.

## Features

*   **⚡ Zig Performance**: Written in Zig 0.14 for speed, safety, and zero dependencies.
*   **🧠 Autonomous Tools**:
    *   **Filesystem**: Read/Write/Diff files.
    *   **Execution**: Run safe shell commands (`exec.run`).
    *   **Git**: Integration for version control.
    *   **LSP**: Orchestrate Language Servers (ZLS, Gopls, etc.).
*   **🧵 Concurrency**: Supports multiple simultaneous agents via TCP threading.
*   **🛠️ Emacs Integration**: Seamless bi-directional RPC with `zemacs-client.el`.

## Installation

### Prerequisites
*   **Zig 0.14+** (Nightly/Dev)
*   Emacs 29+ (for client)

### Build
```bash
git clone https://github.com/yourusername/zemacs.git
cd zemacs
zig build
```

The binary will be at `./zig-out/bin/zemacs`.

## Usage

### 1. TCP Mode (Multi-Agent)
Run the server in TCP mode to allow multiple connections:
```bash
./zig-out/bin/zemacs -mode tcp -port 3000
```
Connect via `nc` or any MCP client:
```bash
echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}' | nc 127.0.0.1 3000
```

### 2. Standard IO (Single Agent)
Ideal for direct integration with MCP clients (like Claude Desktop or Cursor):
```bash
./zig-out/bin/zemacs
```

### 3. Emacs Client
Add `clients/emacs/zemacs-client.el` to your load path:
```elisp
(require 'zemacs-client)
(zemacs-connect) ;; Connects to localhost:3000
```

For configuration guides for **Claude Desktop**, **Windsurf**, and **Cursor**, see [docs/CLIENTS.md](docs/CLIENTS.md).

## Architecture

*   **Transport**: Supports `stdio` and `tcp` (Thread-per-Connection).
*   **Memory**: Request-scoped Arena Allocators for leak-free stability.
*   **Protocol**: JSON-RPC 2.0.

## License
MIT
