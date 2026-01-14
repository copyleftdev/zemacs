const std = @import("std");
const net = std.net;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: zemacs-client <tool> [args...]\n", .{});
        std.debug.print("Example: zemacs-client echo '{{\"message\": \"hello\"}}'\n", .{});
        return;
    }

    const tool_name = args[1];
    var json_args: []const u8 = "{}";
    if (args.len > 2) {
        json_args = args[2];
    }

    // validate JSON
    var parsed_args = try std.json.parseFromSlice(std.json.Value, allocator, json_args, .{});
    defer parsed_args.deinit();

    const address = try net.Address.parseIp("127.0.0.1", 3000);
    const stream = try net.tcpConnectToAddress(address);
    defer stream.close();

    const writer = stream.writer();
    const reader = stream.reader();

    // Construct JSON-RPC Request
    // Request: {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "tool", "arguments": { ... }}}

    var params_map = std.json.ObjectMap.init(allocator);
    defer params_map.deinit();
    try params_map.put("name", std.json.Value{ .string = tool_name });
    try params_map.put("arguments", parsed_args.value);

    const rpc_req = struct {
        jsonrpc: []const u8 = "2.0",
        id: i32 = 1,
        method: []const u8 = "tools/call",
        params: std.json.Value,
    }{
        .params = std.json.Value{ .object = params_map },
    };

    const req_str = try std.json.stringifyAlloc(allocator, rpc_req, .{});
    defer allocator.free(req_str);

    try writer.writeAll(req_str);
    try writer.writeAll("\n");

    // Read response
    const payload = try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 10 * 1024 * 1024);
    if (payload) |p| {
        defer allocator.free(p);
        std.debug.print("{s}\n", .{p});
    }
}
