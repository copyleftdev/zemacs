const std = @import("std");
const schema = @import("mcp/schema.zig");
const json = std.json;
const transport_mod = @import("transport/stdio.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse Args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var mode_tcp = false;
    var port: u16 = 3000;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-mode")) {
            if (i + 1 < args.len) {
                if (std.mem.eql(u8, args[i + 1], "tcp")) {
                    mode_tcp = true;
                }
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "-port")) {
            if (i + 1 < args.len) {
                port = try std.fmt.parseInt(u16, args[i + 1], 10);
                i += 1;
            }
        }
    }

    if (mode_tcp) {
        const address = try std.net.Address.parseIp("127.0.0.1", port);
        // Deprecated: var server = std.net.StreamServer.init(.{ .reuse_address = true });
        // New in 0.14/dev:
        var server = try address.listen(.{ .reuse_address = true });
        defer server.deinit();
        // try server.listen(address); // listen is now called directly on address or via net.listen

        std.debug.print("ZEMACS Listening on 127.0.0.1:{d}...\n", .{port});

        while (true) {
            const conn = try server.accept();
            // Spawn thread
            const thread = try std.Thread.spawn(.{}, handleConnection, .{ allocator, conn });
            thread.detach();
        }
    } else {
        // Stdio Mode (Default)
        // ... (existing code for processLoop)
        var transport = transport_mod.StdioTransport.init();
        transport_mod.global_transport = &transport;
        try processLoop(transport_mod.StdioTransport, &transport, allocator);
    }
}

// ... processLoop ...

fn handleConnection(allocator: std.mem.Allocator, conn: std.net.Server.Connection) void {
    defer conn.stream.close();
    const transport_tcp = @import("transport/tcp.zig");
    var transport = transport_tcp.TcpTransport.init(conn);

    processLoop(transport_tcp.TcpTransport, &transport, allocator) catch |err| {
        std.debug.print("Connection error: {}\n", .{err});
    };
}

// Generic Processing Loop
fn processLoop(comptime TransportType: type, transport: *TransportType, gpa_allocator: std.mem.Allocator) !void {
    const manifest = @import("tools/manifest.zig");
    const protocol = @import("mcp/protocol.zig");

    while (true) {
        // 1. Initialize Arena for this request
        var arena = std.heap.ArenaAllocator.init(gpa_allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        // Use GPA for reading the message line to avoid arena lifetime issues if we decoupled
        // but here we keep it simple.
        const line = transport.readNextMessage(gpa_allocator) catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };

        if (line) |l| {
            defer gpa_allocator.free(l);
            const trimmed = std.mem.trim(u8, l, " \t\r\n");
            if (trimmed.len == 0) continue;

            const parsed = std.json.parseFromSlice(protocol.JsonRpcRequest, arena_alloc, trimmed, .{ .ignore_unknown_fields = true }) catch {
                continue;
            };

            const req = parsed.value;

            if (std.mem.eql(u8, req.method, "tools/list")) {
                const result = try manifest.ToolRegistry.listTools(arena_alloc);
                const result_str = try std.json.stringifyAlloc(arena_alloc, result, .{});
                const result_val_parsed = try std.json.parseFromSlice(json.Value, arena_alloc, result_str, .{});

                const resp = protocol.JsonRpcResponse{
                    .id = req.id,
                    .result = result_val_parsed.value,
                };
                const resp_str = try std.json.stringifyAlloc(arena_alloc, resp, .{});
                try transport.sendMessage(resp_str);
                continue;
            }

            if (std.mem.eql(u8, req.method, "tools/call")) {
                if (req.params) |params| {
                    if (params.object.get("name")) |tool_name_v| {
                        const tool_name = tool_name_v.string;
                        const args = params.object.get("arguments");

                        const result = manifest.ToolRegistry.execute(arena_alloc, tool_name, args) catch |err| {
                            const err_resp = protocol.JsonRpcResponse{
                                .id = req.id,
                                .error_obj = protocol.JsonRpcError{ .code = -32000, .message = @errorName(err) },
                            };
                            const err_str = try std.json.stringifyAlloc(arena_alloc, err_resp, .{});
                            try transport.sendMessage(err_str);
                            continue;
                        };

                        const resp = protocol.JsonRpcResponse{
                            .id = req.id,
                            .result = result,
                        };
                        const resp_str = try std.json.stringifyAlloc(arena_alloc, resp, .{});
                        try transport.sendMessage(resp_str);
                    }
                }
                continue;
            }
        } else {
            break;
        }
    }
}

test "schema generation" {
    const TestArgs = struct {
        filename: []const u8,
        count: i32,
        force: ?bool,
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = try schema.generateSchema(allocator, TestArgs);

    // Check if keys exist.
    // Note: json.Value is a tagged union. .object is a StringHashMap.
    try std.testing.expect(result == .object);

    // properties
    const props = result.object.get("properties").?;
    try std.testing.expect(props == .object);

    try std.testing.expect(props.object.contains("filename"));
    try std.testing.expect(props.object.contains("count"));
    try std.testing.expect(props.object.contains("force"));

    // required
    const required = result.object.get("required").?;
    try std.testing.expect(required == .array);
    try std.testing.expect(required.array.items.len == 2);

    // We could inspect the contents of required array, but this is a good smoke test.
}

test "tool registry" {
    const manifest = @import("tools/manifest.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = try manifest.ToolRegistry.listTools(allocator);
    try std.testing.expectEqual(@as(usize, 1), result.tools.len);
    try std.testing.expect(std.mem.eql(u8, "echo", result.tools[0].name));

    // Test execution
    var args_map = std.json.ObjectMap.init(allocator);
    try args_map.put("message", json.Value{ .string = "Hello Dispatch" });

    const exec_res = try manifest.ToolRegistry.execute(allocator, "echo", json.Value{ .object = args_map });
    // std.debug.print("Exec Result: {any}\n", .{exec_res});
    try std.testing.expect(std.mem.eql(u8, "Hello Dispatch", exec_res.string));
}
