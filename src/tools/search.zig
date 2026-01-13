const std = @import("std");
const json = std.json;

pub const ProjectTree = struct {
    pub const name = "project.tree";
    pub const description = "Lists directory structure (visual tree)";

    pub const Args = struct {
        path: ?[]const u8 = null,
        depth: ?i32 = null,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        const root_path = if (args.path) |p| p else ".";
        const max_depth = if (args.depth) |d| d else 2;

        var buffer = std.ArrayList(u8).init(allocator);

        try walk(allocator, root_path, 0, max_depth, &buffer);

        return json.Value{ .string = try buffer.toOwnedSlice() };
    }

    fn walk(allocator: std.mem.Allocator, path: []const u8, current_depth: i32, max_depth: i32, buffer: *std.ArrayList(u8)) !void {
        if (current_depth > max_depth) return;

        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
            try buffer.writer().print("{s} [Error: {s}]\n", .{ path, @errorName(err) });
            return;
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            // Indentation
            var i: i32 = 0;
            while (i < current_depth) : (i += 1) {
                try buffer.appendSlice("  ");
            }

            // Output name
            try buffer.writer().print("{s}", .{entry.name});

            if (entry.kind == .directory) {
                try buffer.appendSlice("/\n");
                // Recurse
                const next_path = try std.fs.path.join(allocator, &.{ path, entry.name });
                defer allocator.free(next_path);
                try walk(allocator, next_path, current_depth + 1, max_depth, buffer);
            } else {
                try buffer.appendSlice("\n");
            }
        }
    }
};

pub const SearchFiles = struct {
    pub const name = "search.files";
    pub const description = "Fuzzy/Glob search for files by name";

    pub const Args = struct {
        path: ?[]const u8 = null,
        pattern: []const u8,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        const root_path = if (args.path) |p| p else ".";
        var results = std.ArrayList([]const u8).init(allocator);

        try walkSearch(allocator, root_path, args.pattern, &results);

        // Join results with newlines
        var buffer = std.ArrayList(u8).init(allocator);
        for (results.items) |res| {
            try buffer.writer().print("{s}\n", .{res});
        }

        return json.Value{ .string = try buffer.toOwnedSlice() };
    }

    fn walkSearch(allocator: std.mem.Allocator, path: []const u8, pattern: []const u8, results: *std.ArrayList([]const u8)) !void {
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            // Simple substring match for "fuzzy"
            if (std.mem.indexOf(u8, entry.name, pattern) != null) {
                const full_path = try std.fs.path.join(allocator, &.{ path, entry.name });
                try results.append(full_path);
            }

            if (entry.kind == .directory) {
                // Skip hidden dirs (simple heuristic)
                if (entry.name[0] == '.') continue;

                const next_path = try std.fs.path.join(allocator, &.{ path, entry.name });
                defer allocator.free(next_path);
                try walkSearch(allocator, next_path, pattern, results);
            }
        }
    }
};

pub const SearchGrep = struct {
    pub const name = "search.grep";
    pub const description = "Search for a string in file contents";

    pub const Args = struct {
        path: ?[]const u8 = null,
        query: []const u8,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        const root_path = if (args.path) |p| p else ".";
        var buffer = std.ArrayList(u8).init(allocator);

        try walkGrep(allocator, root_path, args.query, &buffer);

        return json.Value{ .string = try buffer.toOwnedSlice() };
    }

    fn walkGrep(allocator: std.mem.Allocator, path: []const u8, query: []const u8, buffer: *std.ArrayList(u8)) !void {
        // Try to open as file first? Or assume path is dir?
        // Let's assume recursion from root.

        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.name[0] == '.') continue;

            const full_path = try std.fs.path.join(allocator, &.{ path, entry.name });
            defer allocator.free(full_path);

            if (entry.kind == .file) {
                // Check content
                const file = std.fs.cwd().openFile(full_path, .{}) catch continue;
                defer file.close();

                // Stream the file line by line using a buffered reader
                var buf_reader = std.io.bufferedReader(file.reader());
                var in_stream = buf_reader.reader();

                var buf: [4096]u8 = undefined;
                var line_no: usize = 1;

                while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
                    if (std.mem.indexOf(u8, line, query) != null) {
                        try buffer.writer().print("{s}:{d}: {s}\n", .{ full_path, line_no, line });
                    }
                    line_no += 1;
                }
            } else if (entry.kind == .directory) {
                try walkGrep(allocator, full_path, query, buffer);
            }
        }
    }
};
