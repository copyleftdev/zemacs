const std = @import("std");
const protocol = @import("mcp/protocol.zig");
const json = std.json;

/// Fuzzing Harness
/// Reads all bytes from stdin and attempts to parse them as a JsonRpcRequest.
/// This targets the std.json parser and our protocol definitions.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read all input from stdin (limit 10MB to avoid OOM in fuzz loop)
    const stdin = std.io.getStdIn().reader();
    const input = stdin.readAllAlloc(allocator, 10 * 1024 * 1024) catch |err| {
        // Failing to read input is not a crash, just exit
        if (err == error.StreamTooLong) return; // Ignore oversize
        return;
    };
    defer allocator.free(input);

    // Prepare Arena for parsing
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Attempt Parse
    const parsed = std.json.parseFromSlice(protocol.JsonRpcRequest, arena_alloc, input, .{ .ignore_unknown_fields = true }) catch {
        // Parsing error is EXPECTED for garbage input.
        // We only care if it panics/crashes.
        return;
    };

    // If we get here, it parsed valid JSON (structurally).
    // Access fields to ensure no hidden lazy-eval panics
    const req = parsed.value;
    _ = req.jsonrpc;
    _ = req.method;
    _ = req.id;
    // Done.
}
