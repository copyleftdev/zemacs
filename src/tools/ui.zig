const std = @import("std");
const json = std.json;
const transport_mod = @import("../transport/stdio.zig");
const protocol = @import("../mcp/protocol.zig");

pub const UiAskUser = struct {
    pub const name = "ui.ask_user";
    pub const description = "Asks the user for input via the client.";

    pub const Args = struct {
        prompt: []const u8,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        const transport = transport_mod.global_transport orelse return error.NoTransport;

        // 1. Send Request
        // We need a structured Request object for 'client/request' (or whatever usage pattern)
        // Since MCP doesn't standardize "ask user", we use a custom method 'zemacs/ask_user' or 'client/sampling'.
        // Let's use 'client/call' if we treat client as a server, OR just 'zemacs/ask' notification?
        // No, we need a response. So it's a Request.

        const req_id = std.time.nanoTimestamp(); // Simple ID

        // Construct params manually for flexibility
        var params_map = std.json.ObjectMap.init(allocator);
        defer params_map.deinit();
        try params_map.put("prompt", json.Value{ .string = args.prompt });

        const req = protocol.JsonRpcRequest{
            .jsonrpc = "2.0",
            .id = json.Value{ .integer = @intCast(req_id) },
            .method = "zemacs/ask_user", // Client must implement this!
            .params = json.Value{ .object = params_map },
        };

        const req_str = try std.json.stringifyAlloc(allocator, req, .{});
        defer allocator.free(req_str);

        try transport.sendMessage(req_str);

        // 2. Wait for Response
        while (true) {
            const line = try transport.readNextMessage(allocator);
            if (line) |l| {
                defer allocator.free(l);
                const trimmed = std.mem.trim(u8, l, " \t\r\n");
                if (trimmed.len == 0) continue;

                // We only care about Responses with matching ID
                // Try to parse as Response
                // Only parse enough to get ID?
                // Let's parse as Response struct.

                const parsed = std.json.parseFromSlice(protocol.JsonRpcResponse, allocator, trimmed, .{ .ignore_unknown_fields = true }) catch {
                    // Not a response (maybe a request?), ignore
                    continue;
                };
                defer parsed.deinit();

                const resp = parsed.value;

                // Check ID
                const id = resp.id;
                if (id == .integer) {
                    if (id.integer == req_id) {
                        // Found it!
                        if (resp.error_obj) |_| { // Ignore error detail for now
                            return error.UserCancelled; // Simplified
                        }
                        if (resp.result) |res| {
                            // Clone the result because 'parsed' will be freed
                            const s = try std.json.stringifyAlloc(allocator, res, .{});
                            defer allocator.free(s);
                            const cloned = try std.json.parseFromSlice(json.Value, allocator, s, .{});
                            return cloned.value;
                        }
                    }
                }
            } else {
                return error.EndOfStream;
            }
        }
    }
};
