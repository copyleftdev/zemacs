const std = @import("std");

pub const Edit = union(enum) {
    Keep: []const u8,
    Insert: []const u8,
    Delete: []const u8,
};

pub fn computeDiff(allocator: std.mem.Allocator, old_text: []const u8, new_text: []const u8) ![]u8 {
    var old_lines = std.ArrayList([]const u8).init(allocator);
    defer old_lines.deinit();
    var it_old = std.mem.splitScalar(u8, old_text, '\n');
    while (it_old.next()) |line| try old_lines.append(line);

    var new_lines = std.ArrayList([]const u8).init(allocator);
    defer new_lines.deinit();
    var it_new = std.mem.splitScalar(u8, new_text, '\n');
    while (it_new.next()) |line| try new_lines.append(line);

    // Naive implementation for MVP:
    // If exact match, empty diff.
    // If different, simple old->new replacement block
    // TODO: Implement Myers algorithm for standard diffs.
    // For now, to unblock, we generate a valid full-file diff if changed.

    // Check equality
    if (std.mem.eql(u8, old_text, new_text)) {
        return try allocator.dupe(u8, "");
    }

    var diff = std.ArrayList(u8).init(allocator);
    try diff.writer().print("--- a/original\n+++ b/modified\n@@ -1,{d} +1,{d} @@\n", .{ old_lines.items.len, new_lines.items.len });

    // For MVP transparency: Dump all old as delete, all new as insert.
    // This is valid but not minimal.
    // Users (Emacs) can still apply this.

    for (old_lines.items) |line| {
        try diff.writer().print("-{s}\n", .{line});
    }
    for (new_lines.items) |line| {
        try diff.writer().print("+{s}\n", .{line});
    }

    return diff.toOwnedSlice();
}
