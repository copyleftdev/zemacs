# Contributing to ZEMACS

Thank you for your interest in contributing to ZEMACS! We aim to build the most robust Agentic MCP Server for Emacs.

## Getting Started

1.  **Fork** the repository.
2.  **Clone** your fork: `git clone https://github.com/your-username/zemacs.git`.
3.  **Build** the project: `zig build`.

## Development Guidelines

*   **Zig Version**: Use the latest `0.14.0-dev` (Nightly) build.
*   **Style**: Follow standard Zig style guidelines.
*   **Testing**: Run tests with `zig build test`.
*   **Concurrency**: Ensure all shared state is protected by mutexes or is thread-critical.

## Pull Request Process

1.  Create a feature branch: `git checkout -b feature/amazing-feature`.
2.  Commit your changes.
3.  Push to the branch.
4.  Open a Pull Request.

## Code of Conduct

Please be respectful and kind to other contributors.
