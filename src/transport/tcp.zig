const std = @import("std");

/// Handles communication over a TCP connection
pub const TcpTransport = struct {
    conn: std.net.Server.Connection,
    reader: std.net.Stream.Reader,
    writer: std.net.Stream.Writer,

    pub fn init(conn: std.net.Server.Connection) TcpTransport {
        return TcpTransport{
            .conn = conn,
            .reader = conn.stream.reader(),
            .writer = conn.stream.writer(),
        };
    }

    /// Reads the next newline-delimited JSON message using the provided allocator.
    /// Caller owns the returned slice.
    /// Returns null if connection is closed.
    pub fn readNextMessage(self: *TcpTransport, allocator: std.mem.Allocator) !?[]u8 {
        // Use a buffered reader potentially? For now, readUntilDelimiterAlloc is fine.
        // Note: TCP streams might return partial reads, but readUntilDelimiterAlloc handles buffering
        // internally or we rely on the stream reader.
        // Actually, for robust production use, we want a Buffered Reader on top of the stream.
        // But let's stick to the simplest working implementation first.

        const line = self.reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 10 * 1024 * 1024) catch |err| {
            if (err == error.EndOfStream) return null;
            return err;
        };
        return line;
    }

    /// Sends a message string followed by a newline.
    pub fn sendMessage(self: *TcpTransport, msg: []const u8) !void {
        // We write the message + newline atomically if possible, or just sequential writes.
        // Using a mutex here might be needed if multiple threads write to the same socket?
        // But in our model, one thread owns one socket. So no mutex needed for the socket writer.
        try self.writer.writeAll(msg);
        try self.writer.writeAll("\n");
    }
};
