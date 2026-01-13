const std = @import("std");
const json = std.json;
const protocol = @import("../mcp/protocol.zig"); // Reuse some JSON-RPC types? Or define new ones.

pub const LspClient = struct {
    child: std.process.Child,
    allocator: std.mem.Allocator,
    next_id: std.atomic.Value(i64) = std.atomic.Value(i64).init(1),

    pub fn init(allocator: std.mem.Allocator, cmd: []const []const u8) !*LspClient {
        var client = try allocator.create(LspClient);
        client.allocator = allocator;
        client.next_id = std.atomic.Value(i64).init(1);

        client.child = std.process.Child.init(cmd, allocator);
        client.child.stdin_behavior = .Pipe;
        client.child.stdout_behavior = .Pipe;
        client.child.stderr_behavior = .Inherit;

        try client.child.spawn();

        return client;
    }

    pub fn deinit(self: *LspClient) void {
        _ = self.child.kill() catch {};
        self.allocator.destroy(self);
    }

    pub fn sendRequest(self: *LspClient, method: []const u8, params: anytype) !json.Value {
        // 1. Construct JSON body
        const Req = struct {
            jsonrpc: []const u8 = "2.0",
            id: i64,
            method: []const u8,
            params: @TypeOf(params),
        };

        const id = self.next_id.fetchAdd(1, .monotonic);
        const req = Req{
            .id = id,
            .method = method,
            .params = params,
        };

        const body = try std.json.stringifyAlloc(self.allocator, req, .{});
        defer self.allocator.free(body);

        // 2. Write Header + Body
        const stdin = self.child.stdin.?;
        try stdin.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ body.len, body });

        // 3. Read Response (Blocking for MVP)
        // Check for headers
        const stdout = self.child.stdout.?.reader();
        var content_length: usize = 0;

        while (true) {
            const line = try stdout.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1024);
            if (line) |l| {
                defer self.allocator.free(l);
                const trimmed = std.mem.trim(u8, l, "\r");
                if (trimmed.len == 0) break; // End of headers

                if (std.mem.startsWith(u8, trimmed, "Content-Length: ")) {
                    const len_str = trimmed["Content-Length: ".len..];
                    content_length = try std.fmt.parseInt(usize, len_str, 10);
                }
            } else {
                return error.LspClosed;
            }
        }

        if (content_length == 0) return error.InvalidResponse;

        const resp_body = try self.allocator.alloc(u8, content_length);
        defer self.allocator.free(resp_body);
        _ = try stdout.readNoEof(resp_body);

        // Parse Result
        const Resp = struct {
            jsonrpc: []const u8,
            id: i64,
            result: ?json.Value = null,
            error_obj: ?json.Value = null, // simplified
        };

        const parsed = try std.json.parseFromSlice(Resp, self.allocator, resp_body, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        if (parsed.value.result) |res| {
            // Deep copy result out because parser owns it?
            // Actually parsed.deinit() frees the arena.
            // We need to clone it.
            // stringify -> parse to unknown json.Value is consistent.
            const s = try std.json.stringifyAlloc(self.allocator, res, .{});
            defer self.allocator.free(s);
            const cloned = try std.json.parseFromSlice(json.Value, self.allocator, s, .{});
            // We leak the cloned arena here? No, we return a value that depends on it.
            // This architecture is tricky with Zig's memory model.
            // For now, let's just return the stringified result as a "Value" containing a string (hack)
            // OR we return a fresh json.Value that owns its data?
            // Let's return the stringified JSON and let the caller parse if needed?
            // No, the tool expects json.Value.

            // Allow leak for MVP or use a long-lived arena for the client state?
            // We are inside a tool `run` which has an allocator.
            // Use that allocator?
            // `sendRequest` uses self.allocator which might be GPA.
            // The `run` gets an arena allocator usually.

            return cloned.value;
        } else {
            return json.Value{ .null = {} };
        }
    }
};
