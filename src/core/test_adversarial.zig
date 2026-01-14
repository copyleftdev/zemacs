const std = @import("std");
const GapBuffer = @import("buffer.zig").GapBuffer;
const UndoManager = @import("undo.zig").UndoManager;
const Marker = @import("buffer.zig").Marker;

/// A simple reference buffer using std.ArrayList for truth comparison.
const ReferenceBuffer = struct {
    data: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) ReferenceBuffer {
        return .{ .data = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *ReferenceBuffer) void {
        self.data.deinit();
    }

    pub fn insert(self: *ReferenceBuffer, pos: usize, text: []const u8) !void {
        try self.data.insertSlice(pos, text);
    }

    pub fn delete(self: *ReferenceBuffer, pos: usize, count: usize) void {
        const actual_count = @min(count, self.data.items.len - pos);
        // data.replaceRange(pos, actual_count, &[_]u8{}) is one way, or orderedRemove
        // ArrayList doesn't have a bulk remove? It has replaceRange.
        self.data.replaceRange(pos, actual_count, &[0]u8{}) catch unreachable;
    }

    pub fn checkEqual(self: *ReferenceBuffer, gb: GapBuffer) !void {
        const gb_slice = try gb.toOwnedSlice();
        defer gb.allocator.free(gb_slice);

        if (!std.mem.eql(u8, self.data.items, gb_slice)) {
            std.debug.print("\nMISMATCH:\nRef: '{s}'\nGap: '{s}'\n", .{ self.data.items, gb_slice });
            return error.TestExpectedEqualStrings;
        }
    }
};

test "Adversarial Fuzzing: GapBuffer vs Reference" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0x1337); // Fixed seed for reproducibility
    const rand = prng.random();

    var ref = ReferenceBuffer.init(allocator);
    defer ref.deinit();

    var gb = try GapBuffer.init(allocator, 10);
    defer gb.deinit();

    const iterations = 5000;
    const max_insert_len = 50;
    const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ";

    for (0..iterations) |i| {
        const op = rand.intRangeAtMost(u8, 0, 10);
        const len = gb.len(); // Use gb.len() as the current truth length for range calculations

        if (op < 6) { // 60% Insert
            const insert_len = rand.intRangeAtMost(usize, 1, max_insert_len);
            const pos = rand.intRangeAtMost(usize, 0, len);

            // Generate garbage text
            var text = try allocator.alloc(u8, insert_len);
            defer allocator.free(text);
            for (0..insert_len) |c| text[c] = charset[rand.uintLessThan(usize, charset.len)];

            // Apply to both
            try ref.insert(pos, text);
            try gb.insert(pos, text);
        } else { // 40% Delete
            if (len == 0) continue;
            const del_len = rand.intRangeAtMost(usize, 1, max_insert_len); // Can be larger than buffer
            const pos = rand.intRangeAtMost(usize, 0, len - 1);

            ref.delete(pos, del_len);
            gb.delete(pos, del_len);
        }

        // Verify every 50 steps to catch drift early, or every step?
        // Every step is safer for adversarial.
        ref.checkEqual(gb) catch |err| {
            std.debug.print("Failure at iteration {}\n", .{i});
            return err;
        };
    }
}

test "Adversarial Fuzzing: Undo/Redo Cycles" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xDEADBEEF);
    const rand = prng.random();

    var gb = try GapBuffer.init(allocator, 100);
    defer gb.deinit();

    var undo_mgr = UndoManager.init(allocator);
    defer undo_mgr.deinit();

    // We keep a history of states to verify undo
    var history = std.ArrayList([]u8).init(allocator);
    defer {
        for (history.items) |h| allocator.free(h);
        history.deinit();
    }

    // Push initial state
    try history.append(try gb.toOwnedSlice());

    const iterations = 1000;

    // We will perform actions. If we undo, we pop from history reference.
    // If we perform new action, we push to history reference.

    var undo_depth: usize = 0; // tracking how far back we are

    for (0..iterations) |i| {
        // Op types:
        // 0-6: New Edit (Insert/Delete)
        // 7-8: Undo
        // 9: Redo

        const op = rand.intRangeAtMost(u8, 0, 10);
        const current_len = gb.len();

        if (op <= 7) {
            // NEW EDIT
            // If we were in undo state (undo_depth > 0), performing a new action
            // will truncate the history of "future" states effectively.
            // But wait, my simple history list is linear.
            // If I am at state K out of N states in my history list...
            // Emacs undo is linear but "undoing an undo" adds to the end.
            // My reference history model here is stricter: checking "traditional" stack undo.
            // My UndoManager is stack-based.

            // If undo_depth > 0, we lose the ability to redo to the old tips.
            // So we should truncate our reference history.
            if (undo_depth > 0) {
                const keep_count = history.items.len - undo_depth;
                // Free dropped history
                for (history.items[keep_count..]) |h| allocator.free(h);
                history.shrinkRetainingCapacity(keep_count);
                undo_depth = 0;
            }

            try undo_mgr.beginGroup();

            const sub_op = rand.boolean();
            if (sub_op) {
                // Insert
                const pos = rand.intRangeAtMost(usize, 0, current_len);
                try gb.insert(pos, "x");
                try undo_mgr.recordInsert(pos, 1);
            } else {
                // Delete
                if (current_len > 0) {
                    const pos = rand.intRangeAtMost(usize, 0, current_len - 1);
                    // Copy functionality check
                    var buf: [1]u8 = undefined;
                    gb.copyAt(pos, 1, &buf);

                    try undo_mgr.recordDelete(pos, &buf);
                    gb.delete(pos, 1);
                }
            }
            try undo_mgr.endGroup();

            // Save new state
            try history.append(try gb.toOwnedSlice());
        } else if (op <= 9) {
            // UnDO
            if (try undo_mgr.undo(&gb)) {
                undo_depth += 1;

                // Verify
                const expected_idx = history.items.len - 1 - undo_depth;
                const expected = history.items[expected_idx];

                const actual = try gb.toOwnedSlice();
                defer allocator.free(actual);

                if (!std.mem.eql(u8, expected, actual)) {
                    std.debug.print("Undo Mismatch at iter {}: Expected '{s}', Got '{s}'\n", .{ i, expected, actual });
                    return error.UndoMismatch;
                }
            }
        } else {
            // REDO
            if (try undo_mgr.redo(&gb)) {
                if (undo_depth > 0) {
                    undo_depth -= 1;

                    const expected_idx = history.items.len - 1 - undo_depth;
                    const expected = history.items[expected_idx];

                    const actual = try gb.toOwnedSlice();
                    defer allocator.free(actual);

                    if (!std.mem.eql(u8, expected, actual)) {
                        std.debug.print("Redo Mismatch at iter {}: Expected '{s}', Got '{s}'\n", .{ i, expected, actual });
                        return error.RedoMismatch;
                    }
                }
            }
        }
    }
}
