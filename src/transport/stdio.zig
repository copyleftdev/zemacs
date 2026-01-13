const std = @import("std");
const types = @import("../types.zig");

// Global singleton hook for tools to access transport (MVP Hack)
// In a production system, this would be passed via context to tools.
pub var global_transport: ?*StdioTransport = null;

pub const StdioTransport = struct {
    reader: std.io.BufferedReader(4096, std.fs.File.Reader),
    writer: std.fs.File.Writer,
    // Add lock for thread safety if we were multi-threaded

    pub fn init() StdioTransport {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();
        return StdioTransport{
            .reader = std.io.bufferedReader(stdin),
            .writer = stdout,
        };
    }

    /// Reads a single line from stdin. Caller owns the memory.
    /// Returns null on EOF.
    pub fn readNextMessage(self: *StdioTransport, allocator: std.mem.Allocator) !?[]u8 {
        const line = try self.reader.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', 10 * 1024 * 1024); // 10MB max line
        return line;
    }

    pub fn sendMessage(self: *StdioTransport, message: []const u8) !void {
        try self.writer.writeAll(message);
        try self.writer.writeAll("\n");
    }
};
