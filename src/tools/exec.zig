const std = @import("std");
const json = std.json;
const process = @import("../utils/process.zig");

pub const ExecRun = struct {
    pub const name = "exec.run";
    pub const description = "Executes a system command safe (no shell interpolation).";

    pub const Args = struct {
        command: []const u8,
        args: ?[]const []const u8 = null,
        cwd: ?[]const u8 = null,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        var argv = std.ArrayList([]const u8).init(allocator);
        defer argv.deinit(); // Added defer deinit which I missed before? No, strictness.

        try argv.append(args.command);
        if (args.args) |a| {
            try argv.appendSlice(a);
        }

        const items: []const []const u8 = argv.items;
        const result = try process.runProcess(allocator, items, args.cwd);
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        const output = try std.fmt.allocPrint(allocator, "Exit Code: {d}\n\nSTDOUT:\n{s}\n\nSTDERR:\n{s}", .{ result.exit_code, result.stdout, result.stderr });

        return json.Value{ .string = output };
    }
};
