const std = @import("std");
const Allocator = std.mem.Allocator;

/// A Marker points to a position in the buffer and moves automatically
/// when text is inserted or deleted.
pub const Marker = struct {
    /// Current byte offset in the buffer (logical position, unaware of gap).
    pos: usize,
    /// If true, the marker moves forward when text is inserted at its position.
    /// If false, it stays behind the inserted text.
    insertion_type: bool,
};

/// A Gap Buffer implementation for efficient text editing.
///
/// Physical layout:
/// [ A B C _ _ _ D E F ]
///        ^     ^
///   gap_start  gap_end
///
/// Logical content: "ABCDEF"
pub const GapBuffer = struct {
    allocator: Allocator,
    data: []u8,
    gap_start: usize,
    gap_end: usize,
    markers: std.ArrayList(*Marker),

    /// Default initial capacity
    const MIN_CAPACITY = 1024;

    pub fn init(allocator: Allocator, capacity: usize) !GapBuffer {
        const cap = @max(capacity, MIN_CAPACITY);
        const data = try allocator.alloc(u8, cap);
        return GapBuffer{
            .allocator = allocator,
            .data = data,
            .gap_start = 0,
            .gap_end = cap, // Gap covers the whole buffer initially
            .markers = std.ArrayList(*Marker).init(allocator),
        };
    }

    pub fn deinit(self: *GapBuffer) void {
        self.allocator.free(self.data);
        self.markers.deinit();
    }

    /// Returns the length of the text in the buffer.
    pub fn len(self: GapBuffer) usize {
        return self.data.len - (self.gap_end - self.gap_start);
    }

    /// Returns the byte at the specified logical position.
    pub fn get(self: GapBuffer, pos: usize) u8 {
        if (pos < self.gap_start) {
            return self.data[pos];
        } else {
            return self.data[self.gap_end + (pos - self.gap_start)];
        }
    }

    /// Moves the gap to the specified logical position.
    fn moveGap(self: *GapBuffer, pos: usize) void {
        const current_pos = self.gap_start;
        if (pos == current_pos) return;

        if (pos < current_pos) {
            // Move gap left
            // [ A B _ _ _ C D ]  current_pos = 2, pos = 1 (A)
            // Move B to after gap
            const amount = current_pos - pos;
            // Source: [pos] to [current_pos]
            // Dest:   [gap_end - amount]
            std.mem.copyBackwards(u8, self.data[self.gap_end - amount .. self.gap_end], self.data[pos..current_pos]);
            self.gap_start = pos;
            self.gap_end -= amount;
        } else {
            // Move gap right
            const amount = pos - current_pos;
            std.mem.copyForwards(u8, self.data[self.gap_start .. self.gap_start + amount], self.data[self.gap_end .. self.gap_end + amount]);
            self.gap_start += amount;
            self.gap_end += amount;
        }
    }

    /// Ensures there is enough space in the gap for `size` bytes.
    fn ensureGap(self: *GapBuffer, size: usize) !void {
        const gap_len = self.gap_end - self.gap_start;
        if (gap_len >= size) return;

        // Resize strategy: Double capacity or at least enough for size + padding
        const current_len = self.len();
        const required = current_len + size;
        const new_capacity = @max(self.data.len * 2, required + MIN_CAPACITY);

        const new_data = try self.allocator.alloc(u8, new_capacity);

        // Copy part before gap
        @memcpy(new_data[0..self.gap_start], self.data[0..self.gap_start]);

        // Calculate new gap end
        const new_gap_len = new_capacity - current_len;
        const new_gap_end = self.gap_start + new_gap_len;

        // Copy part after gap
        const after_len = self.data.len - self.gap_end;
        @memcpy(new_data[new_gap_end .. new_gap_end + after_len], self.data[self.gap_end..self.data.len]);

        self.allocator.free(self.data);
        self.data = new_data;
        self.gap_end = new_gap_end;
    }

    /// Inserts text at the specified logical position.
    pub fn insert(self: *GapBuffer, pos: usize, text: []const u8) !void {
        if (text.len == 0) return;

        // 1. Move gap to position
        self.moveGap(pos);

        // 2. Ensure capacity
        try self.ensureGap(text.len);

        // 3. Insert data
        @memcpy(self.data[self.gap_start .. self.gap_start + text.len], text);
        self.gap_start += text.len;

        // 4. Update markers
        for (self.markers.items) |marker| {
            if (marker.pos > pos or (marker.pos == pos and marker.insertion_type)) {
                marker.pos += text.len;
            }
        }
    }

    /// Deletes `count` bytes starting at `pos`.
    pub fn delete(self: *GapBuffer, pos: usize, count: usize) void {
        if (count == 0) return;

        // 1. Move gap to pos (so that deleted items are immediately after the gap)
        // Wait, efficient deletion in array gap buffer is to move gap to 'pos'
        // Then just expand the gap to cover the deleted items.
        // Actually, if we move gap to `pos`, the items to delete are at `gap_end`.
        self.moveGap(pos);

        // 2. Expand gap (effectively deleting)
        // Check bounds
        const available = self.data.len - self.gap_end;
        const actual_count = @min(count, available);
        self.gap_end += actual_count;

        // 3. Update markers
        const end_pos = pos + actual_count;
        for (self.markers.items) |marker| {
            if (marker.pos >= end_pos) {
                marker.pos -= actual_count;
            } else if (marker.pos > pos) {
                // Inside the deleted region, collapse to start
                marker.pos = pos;
            }
        }
    }

    /// Returns a slice to the logical content. Warning: This allocates a new slice
    /// if the content is split by the gap. For read-only access without allocation,
    /// simpler methods should be used or iterators.
    /// For this MVP, we will provide a `toOwnedSlice` for simplicity in tests.
    pub fn toOwnedSlice(self: GapBuffer) ![]u8 {
        const result = try self.allocator.alloc(u8, self.len());
        @memcpy(result[0..self.gap_start], self.data[0..self.gap_start]);
        const after_len = self.data.len - self.gap_end;
        @memcpy(result[self.gap_start..], self.data[self.gap_end .. self.gap_end + after_len]);
        return result;
    }

    /// Copies data from the buffer at `pos` with `count` into `out`.
    /// `out` must be at least `count` bytes long.
    pub fn copyAt(self: GapBuffer, pos: usize, count: usize, out: []u8) void {
        const gap_len = self.gap_end - self.gap_start;
        var copied: usize = 0;
        var current_src = pos;

        // If pos is before gap
        if (pos < self.gap_start) {
            const chunk = @min(count, self.gap_start - pos);
            @memcpy(out[0..chunk], self.data[pos .. pos + chunk]);
            copied += chunk;
            current_src += chunk;
        }

        if (copied < count) {
            // Need to read after gap
            // Logical position `current_src` corresponds to physical `current_src + gap_len`
            const physical_src = current_src + gap_len;
            const chunk = count - copied;
            @memcpy(out[copied..count], self.data[physical_src .. physical_src + chunk]);
        }
    }

    pub fn addMarker(self: *GapBuffer, marker: *Marker) !void {
        try self.markers.append(marker);
    }
};

test "GapBuffer basic operations" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    var buf = try GapBuffer.init(allocator, 10);
    defer buf.deinit();

    try buf.insert(0, "World");
    const s1 = try buf.toOwnedSlice();
    defer allocator.free(s1);
    try testing.expectEqualStrings("World", s1);

    try buf.insert(0, "Hello ");
    const s2 = try buf.toOwnedSlice();
    defer allocator.free(s2);
    try testing.expectEqualStrings("Hello World", s2);

    try buf.insert(5, ",");
    const s3 = try buf.toOwnedSlice();
    defer allocator.free(s3);
    try testing.expectEqualStrings("Hello, World", s3);

    buf.delete(5, 1);
    const s4 = try buf.toOwnedSlice();
    defer allocator.free(s4);
    try testing.expectEqualStrings("Hello World", s4);
}

test "GapBuffer resizing" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    var buf = try GapBuffer.init(allocator, 4); // Small initial
    defer buf.deinit();

    try buf.insert(0, "1234");
    try buf.insert(4, "5678"); // Should resize
    const s = try buf.toOwnedSlice();
    defer allocator.free(s);
    try testing.expectEqualStrings("12345678", s);
}

test "GapBuffer markers" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    var buf = try GapBuffer.init(allocator, 100);
    defer buf.deinit();

    try buf.insert(0, "ABC");

    var m1 = Marker{ .pos = 1, .insertion_type = false }; // At 'B', stay before
    var m2 = Marker{ .pos = 1, .insertion_type = true }; // At 'B', move after

    try buf.addMarker(&m1);
    try buf.addMarker(&m2);

    // Insert 'X' at 1 (before 'B')
    try buf.insert(1, "X");
    // Content: "AXBC"

    // m1 was at 1. insertion was at 1. type=false. Should stay 1.
    // m2 was at 1. insertion was at 1. type=true. Should move to 1+1=2.

    try testing.expectEqual(@as(usize, 1), m1.pos);
    try testing.expectEqual(@as(usize, 2), m2.pos);

    // Delete 'X' at 1
    buf.delete(1, 1);
    // Content: "ABC"

    try testing.expectEqual(@as(usize, 1), m1.pos);
    try testing.expectEqual(@as(usize, 1), m2.pos);
}
