const std = @import("std");
const Allocator = std.mem.Allocator;
const GapBuffer = @import("buffer.zig").GapBuffer;
const Marker = @import("buffer.zig").Marker;

pub const UndoEntry = union(enum) {
    insert: struct { pos: usize, len: usize },
    delete: struct { pos: usize, text: []u8 },
    marker: struct { marker: *Marker, old_pos: usize },
};

pub const UndoManager = struct {
    allocator: Allocator,
    undo_stack: std.ArrayList(std.ArrayList(UndoEntry)),
    redo_stack: std.ArrayList(std.ArrayList(UndoEntry)),
    current_group: ?std.ArrayList(UndoEntry),

    // Safety limit
    max_undo_steps: usize = 1000,

    pub fn init(allocator: Allocator) UndoManager {
        return .{
            .allocator = allocator,
            .undo_stack = std.ArrayList(std.ArrayList(UndoEntry)).init(allocator),
            .redo_stack = std.ArrayList(std.ArrayList(UndoEntry)).init(allocator),
            .current_group = null,
        };
    }

    pub fn deinit(self: *UndoManager) void {
        self.clearStack(&self.undo_stack);
        self.clearStack(&self.redo_stack);
        if (self.current_group) |*g| {
            for (g.items) |entry| {
                self.freeEntry(entry);
            }
            g.deinit();
        }
    }

    fn clearStack(self: *UndoManager, stack: *std.ArrayList(std.ArrayList(UndoEntry))) void {
        for (stack.items) |*group| {
            for (group.items) |entry| {
                self.freeEntry(entry);
            }
            group.deinit();
        }
        stack.deinit();
    }

    fn freeEntry(self: *UndoManager, entry: UndoEntry) void {
        switch (entry) {
            .delete => |d| self.allocator.free(d.text),
            else => {},
        }
    }

    pub fn beginGroup(self: *UndoManager) !void {
        if (self.current_group != null) return;
        self.current_group = std.ArrayList(UndoEntry).init(self.allocator);
    }

    pub fn endGroup(self: *UndoManager) !void {
        if (self.current_group) |group| {
            try self.undo_stack.append(group);
            self.current_group = null;
            // Clear redo stack on new action
            self.clearStack(&self.redo_stack);
            self.redo_stack = std.ArrayList(std.ArrayList(UndoEntry)).init(self.allocator);
        }
    }

    pub fn recordInsert(self: *UndoManager, pos: usize, len: usize) !void {
        if (self.current_group == null) try self.beginGroup();
        // For undoing an insert, we need to know where it was and how long (to delete it)
        try self.current_group.?.append(.{ .insert = .{ .pos = pos, .len = len } });
    }

    pub fn recordDelete(self: *UndoManager, pos: usize, text: []const u8) !void {
        if (self.current_group == null) try self.beginGroup();
        // For undoing a delete, we need the text to re-insert
        const text_copy = try self.allocator.dupe(u8, text);
        try self.current_group.?.append(.{ .delete = .{ .pos = pos, .text = text_copy } });
    }

    pub fn undo(self: *UndoManager, buffer: *GapBuffer) !bool {
        if (self.undo_stack.items.len == 0) return false;

        var group = self.undo_stack.pop() orelse return false;

        // Create redo group
        var redo_group = std.ArrayList(UndoEntry).init(self.allocator);

        // Iterate backwards
        var i: usize = group.items.len;
        while (i > 0) {
            i -= 1;
            const entry = group.items[i];
            switch (entry) {
                .insert => |ins| {
                    // Undo insert = delete

                    // 1. Capture text for Redo (which will be an Insert)
                    const text = try self.allocator.alloc(u8, ins.len);
                    buffer.copyAt(ins.pos, ins.len, text);

                    // 2. Perform Delete
                    buffer.delete(ins.pos, ins.len);

                    // 3. Record Redo (Insert)
                    // Note: 'text' is now owned by the UndoEntry in redo_group
                    try redo_group.append(.{ .delete = .{ .pos = ins.pos, .text = text } });
                },
                .delete => |del| {
                    // Undo delete = insert
                    try buffer.insert(del.pos, del.text);
                    // Redo entry is "Insert" (which logically means we just inserted, so Redo should delete)
                    try redo_group.append(.{ .insert = .{ .pos = del.pos, .len = del.text.len } });
                },
                .marker => |_| {
                    // TODO
                },
            }
            // Free the payload of the processed undo entry
            self.freeEntry(entry);
        }

        try self.redo_stack.append(redo_group);
        group.deinit();

        return true;
    }

    pub fn redo(self: *UndoManager, buffer: *GapBuffer) !bool {
        if (self.redo_stack.items.len == 0) return false;

        var group = self.redo_stack.pop() orelse return false;
        var undo_group = std.ArrayList(UndoEntry).init(self.allocator);

        var i: usize = group.items.len;
        while (i > 0) {
            i -= 1;
            const entry = group.items[i];
            switch (entry) {
                .insert => |ins| {
                    // Redo entry is "Insert" -> We must Delete (undo the insert)

                    // 1. Capture text for Undo
                    const text = try self.allocator.alloc(u8, ins.len);
                    buffer.copyAt(ins.pos, ins.len, text);

                    // 2. Perform Delete
                    buffer.delete(ins.pos, ins.len);

                    // 3. Record Undo (Delete)
                    try undo_group.append(.{ .delete = .{ .pos = ins.pos, .text = text } });
                },
                .delete => |del| {
                    // Redo entry is "Delete" -> We must Insert (undo the delete)
                    try buffer.insert(del.pos, del.text);
                    try undo_group.append(.{ .insert = .{ .pos = del.pos, .len = del.text.len } });
                },
                .marker => |_| {},
            }
            self.freeEntry(entry);
        }

        try self.undo_stack.append(undo_group);
        group.deinit();

        return true;
    }
};
