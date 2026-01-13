const std = @import("std");
const json = std.json;
const process = @import("../utils/process.zig");

fn runGit(allocator: std.mem.Allocator, args: []const []const u8) !json.Value {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("git");
    try argv.appendSlice(args);

    const items: []const []const u8 = argv.items;
    const result = try process.runProcess(allocator, items, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.exit_code != 0) {
        const error_msg = try std.fmt.allocPrint(allocator, "Git Error ({d}): {s}", .{ result.exit_code, result.stderr });
        defer allocator.free(error_msg);
        return json.Value{ .string = try allocator.dupe(u8, error_msg) };
    }

    return json.Value{ .string = try allocator.dupe(u8, result.stdout) };
}

pub const GitStatus = struct {
    pub const name = "git.status";
    pub const description = "Runs 'git status --porcelain'";

    pub const Args = struct {};

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        _ = args;
        const ga = [_][]const u8{ "status", "--porcelain" };
        return runGit(allocator, &ga);
    }
};

pub const GitDiff = struct {
    pub const name = "git.diff";
    pub const description = "Runs 'git diff'";

    pub const Args = struct {
        cached: ?bool = false,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        if (args.cached != null and args.cached.?) {
            const ga = [_][]const u8{ "diff", "--cached" };
            return runGit(allocator, &ga);
        } else {
            const ga = [_][]const u8{"diff"};
            return runGit(allocator, &ga);
        }
    }
};
