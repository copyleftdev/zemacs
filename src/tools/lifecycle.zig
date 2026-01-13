const std = @import("std");
const json = std.json;

pub const ZemacsHealth = struct {
    pub const name = "zemacs.health";
    pub const description = "Returns the health and version of the server.";

    pub const Args = struct {};

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        _ = args;
        var map = std.json.ObjectMap.init(allocator);
        try map.put("status", json.Value{ .string = "ok" });
        try map.put("version", json.Value{ .string = "0.1.0" });
        try map.put("transport", json.Value{ .string = "stdio" });

        return json.Value{ .object = map };
    }
};

pub const ZemacsStatus = struct {
    pub const name = "zemacs.status";
    pub const description = "Returns current server status.";

    pub const Args = struct {};

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        _ = args;
        // In a real implementation this would query active threads, memory, etc.
        // For now just basic info.
        var map = std.json.ObjectMap.init(allocator);
        try map.put("state", json.Value{ .string = "running" });
        try map.put("active_tools", json.Value{ .integer = 0 }); // Placeholder

        return json.Value{ .object = map };
    }
};
