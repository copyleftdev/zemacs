const std = @import("std");
const json = std.json;
const diff_util = @import("../utils/diff.zig");

pub const FsProposeWrite = struct {
    pub const name = "fs.propose_write";
    pub const description = "Generates a unified diff for a proposed file change (does NOT modify file).";

    pub const Args = struct {
        path: []const u8,
        content: []const u8,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        // Read existing file
        const file = std.fs.cwd().openFile(args.path, .{}) catch |err| {
            // If file doesn't exist, treat it as empty for diff (New File)
            if (err == error.FileNotFound) {
                const diff = try diff_util.computeDiff(allocator, "", args.content);
                return json.Value{ .string = diff };
            }
            return json.Value{ .string = try std.fmt.allocPrint(allocator, "Error: {s}", .{@errorName(err)}) };
        };
        defer file.close();

        const old_content = try file.readToEndAlloc(allocator, 100 * 1024 * 1024);
        defer allocator.free(old_content);

        const diff = try diff_util.computeDiff(allocator, old_content, args.content);
        return json.Value{ .string = diff };
    }
};

pub const FsRead = struct {
    pub const name = "fs.read";
    pub const description = "Reads the entire content of a file";

    pub const Args = struct {
        path: []const u8,
    };

    fn validatePath(path: []const u8) !void {
        if (path.len == 0) return error.EmptyPath;
        if (std.mem.indexOf(u8, path, "\x00") != null) return error.InvalidPath;
        // Basic check: Don't allow paths that look like they're trying to escape up too eagerly without being absolute
        // Ideally we resolve to absolute but for now we block nulls and empty.
    }

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        try validatePath(args.path);

        const file = std.fs.cwd().openFile(args.path, .{}) catch |err| {
            // Return helpful error string
            return json.Value{ .string = try std.fmt.allocPrint(allocator, "Error opening file: {s}", .{@errorName(err)}) };
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 100 * 1024 * 1024); // 100MB max
        return json.Value{ .string = content };
    }
};

pub const FsWrite = struct {
    pub const name = "fs.write";
    pub const description = "Writes content to a file (overwrites).";

    pub const Args = struct {
        path: []const u8,
        content: []const u8,
    };

    fn validatePath(path: []const u8) !void {
        if (path.len == 0) return error.EmptyPath;
        if (std.mem.indexOf(u8, path, "\x00") != null) return error.InvalidPath;
    }

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        try validatePath(args.path);

        const file = std.fs.cwd().createFile(args.path, .{}) catch |err| {
            return json.Value{ .string = try std.fmt.allocPrint(allocator, "Error creating file: {s}", .{@errorName(err)}) };
        };
        defer file.close();

        try file.writeAll(args.content);

        return json.Value{ .string = "File written successfully." };
    }
};
