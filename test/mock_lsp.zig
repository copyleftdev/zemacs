const std = @import("std");
const json = std.json;

// Simplified structures for Mock LSP
const JsonRpcRequest = struct {
    jsonrpc: []const u8,
    id: ?json.Value = null,
    method: []const u8,
    params: ?json.Value = null,
};

const JsonRpcResponse = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?json.Value = null,
    result: ?json.Value = null,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    // Using a buffered reader for stdin
    var buffered_stdin = std.io.bufferedReader(stdin);
    const reader = buffered_stdin.reader();

    // Naive header reading - real LSP has 'Content-Length: ...\r\n\r\n' headers
    // But for this mock, we can assume our client implementation might skip headers
    // OR we should implement them to be robust.
    // Let's implement minimal header parsing to be a "real" LSP mock.

    while (true) {
        var content_length: usize = 0;

        // Read headers
        while (true) {
            const line = reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024) catch |err| {
                if (err == error.EndOfStream) return;
                return err;
            };
            if (line) |l| {
                defer allocator.free(l);
                const trimmed = std.mem.trim(u8, l, "\r");
                if (trimmed.len == 0) break; // End of headers

                if (std.mem.startsWith(u8, trimmed, "Content-Length: ")) {
                    const len_str = trimmed["Content-Length: ".len..];
                    content_length = try std.fmt.parseInt(usize, len_str, 10);
                }
            } else {
                return; // EOF
            }
        }

        if (content_length == 0) continue;

        // Read body
        const body = try allocator.alloc(u8, content_length);
        defer allocator.free(body);
        _ = try reader.readNoEof(body);

        // Debug log to stderr
        std.debug.print("MOCK RECV: {s}\n", .{body});

        // Parse JSON
        const parsed = try std.json.parseFromSlice(JsonRpcRequest, allocator, body, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        const req = parsed.value;

        // Handle Request
        var result_json: ?[]const u8 = null;

        if (std.mem.eql(u8, req.method, "initialize")) {
            result_json = "{\"capabilities\": {\"hoverProvider\": true, \"definitionProvider\": true}}";
        } else if (std.mem.eql(u8, req.method, "textDocument/hover")) {
            result_json = "{\"contents\": \"Mock Hover: This is a test symbol\"}";
        } else if (std.mem.eql(u8, req.method, "textDocument/definition")) {
            result_json = "[{\"uri\": \"file:///src/main.zig\", \"range\": {\"start\": {\"line\": 0, \"character\": 0}, \"end\": {\"line\": 0, \"character\": 5}}}]";
        } else {
            result_json = "null";
        }

        // Send Response
        if (req.id) |id| {
            // Construct raw JSON response to avoid complex struct definitions for this mock
            // We reuse the ID from the request

            // Very hacky string building for verification
            // In a real server use std.json.stringify
            var resp_buf = std.ArrayList(u8).init(allocator);
            defer resp_buf.deinit();
            try resp_buf.writer().print("{{\"jsonrpc\":\"2.0\",\"id\":", .{});
            try std.json.stringify(id, .{}, resp_buf.writer());
            try resp_buf.writer().print(",\"result\":{s}}}", .{result_json.?});

            const resp_str = resp_buf.items;

            // Write Header
            try stdout.print("Content-Length: {d}\r\n\r\n", .{resp_str.len});
            try stdout.writeAll(resp_str);
            try stdout.print("\n", .{}); // Extra newline for safety? LSP doesn't require it but good for debug
        }
    }
}
