const std = @import("std");
const GapBuffer = @import("buffer.zig").GapBuffer;
const UndoManager = @import("undo.zig").UndoManager;

test "Undo/Redo Integration" {
    const allocator = std.testing.allocator;

    var buf = try GapBuffer.init(allocator, 100);
    defer buf.deinit();

    var undo_mgr = UndoManager.init(allocator);
    defer undo_mgr.deinit();

    // 1. Insert "Hello"
    try undo_mgr.beginGroup();
    try buf.insert(0, "Hello");
    try undo_mgr.recordInsert(0, 5);
    try undo_mgr.endGroup();

    {
        const s = try buf.toOwnedSlice();
        defer allocator.free(s);
        try std.testing.expectEqualStrings("Hello", s);
    }

    // 2. Insert " World"
    try undo_mgr.beginGroup();
    try buf.insert(5, " World");
    try undo_mgr.recordInsert(5, 6);
    try undo_mgr.endGroup();

    {
        const s = try buf.toOwnedSlice();
        defer allocator.free(s);
        try std.testing.expectEqualStrings("Hello World", s);
    }

    // 3. Undo " World"
    const did_undo = try undo_mgr.undo(&buf);
    try std.testing.expect(did_undo);

    {
        const s = try buf.toOwnedSlice();
        defer allocator.free(s);
        try std.testing.expectEqualStrings("Hello", s);
    }

    // 4. Redo " World"
    const did_redo = try undo_mgr.redo(&buf);
    try std.testing.expect(did_redo);

    {
        const s = try buf.toOwnedSlice();
        defer allocator.free(s);
        try std.testing.expectEqualStrings("Hello World", s);
    }

    // 5. Delete "Hello"
    try undo_mgr.beginGroup();
    // We must record delete BEFORE modifying buffer because recordDelete takes the text
    // ... wait. My 'recordDelete' needs the text.
    // If I delete from buffer first, I can't easily get the text unless I copied it.
    // Let's copy it first.
    const text_to_del = try allocator.alloc(u8, 5);
    buf.copyAt(0, 5, text_to_del);

    try undo_mgr.recordDelete(0, text_to_del); // This makes a copy internally, we own text_to_del
    allocator.free(text_to_del);

    buf.delete(0, 5);
    try undo_mgr.endGroup();

    {
        const s = try buf.toOwnedSlice();
        defer allocator.free(s);
        try std.testing.expectEqualStrings(" World", s);
    }

    // 6. Undo Delete (Restore "Hello")
    try std.testing.expect(try undo_mgr.undo(&buf));

    {
        const s = try buf.toOwnedSlice();
        defer allocator.free(s);
        try std.testing.expectEqualStrings("Hello World", s);
    }
}
