# Build Stage
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y curl xz-utils

WORKDIR /zig
RUN curl -L https://ziglang.org/download/0.14.0/zig-linux-x86_64-0.14.0.tar.xz -o zig.tar.xz && \
    tar -xf zig.tar.xz && \
    mv zig-linux-x86_64-0.14.0 current

ENV PATH="/zig/current:${PATH}"

WORKDIR /app
COPY . .

# Build standard ReleaseSafe executable
RUN zig build -Doptimize=ReleaseSafe --summary all

# Runtime Stage
# Use debian-slim for glibc compatibility (since we build native by default)
# For static binaries, we would target x86_64-linux-musl
FROM debian:bookworm-slim

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/zig-out/bin/zemacs /usr/local/bin/zemacs
COPY --from=builder /app/zig-out/bin/zemacs-client /usr/local/bin/zemacs-client

# Install git and other potential tools needed by the agent
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Default to stdio mode for MCP compatibility
ENTRYPOINT ["/usr/local/bin/zemacs"]
