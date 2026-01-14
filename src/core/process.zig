const std = @import("std");
const Posix = std.posix;
const Allocator = std.mem.Allocator;

/// Represents a running child process managed by ProcessManager.
pub const Process = struct {
    id: i64,
    child: std.process.Child,

    // File descriptors for polling
    stdout_fd: ?Posix.fd_t,
    stderr_fd: ?Posix.fd_t,
    stdin_fd: ?Posix.fd_t,

    pub fn deinit(self: *Process) void {
        _ = self.child.kill() catch {};
        // Child.deinit handles closing FDs if they are owned by it,
        // but we need to check strict ownership rules in Zig's std.process.
        // For now, assume child.deinit/kill is sufficient or handled by manager.
    }
};

/// Manages multiple child processes using a single polling loop (or similar mechanism).
pub const ProcessManager = struct {
    pub const StreamType = enum { stdout, stderr };

    const PollInfo = struct {
        id: i64,
        type: StreamType,
    };

    allocator: Allocator,
    processes: std.AutoHashMap(i64, *Process),
    next_id: i64,

    // Limits
    max_read_size: usize = 4096,

    // Poll structures cache
    poll_fds: std.ArrayList(Posix.pollfd),
    poll_map: std.ArrayList(PollInfo),

    pub fn init(allocator: Allocator) ProcessManager {
        return .{
            .allocator = allocator,
            .processes = std.AutoHashMap(i64, *Process).init(allocator),
            .next_id = 1,
            .poll_fds = std.ArrayList(Posix.pollfd).init(allocator),
            .poll_map = std.ArrayList(PollInfo).init(allocator),
        };
    }

    pub fn deinit(self: *ProcessManager) void {
        var it = self.processes.valueIterator();
        while (it.next()) |proc| {
            proc.*.deinit();
            self.allocator.destroy(proc.*);
        }
        self.processes.deinit();
        self.poll_fds.deinit();
        self.poll_map.deinit();
    }

    /// Spawns a new process with the given arguments.
    /// Returns the process ID.
    pub fn spawn(self: *ProcessManager, argv: []const []const u8) !i64 {
        const id = self.next_id;
        self.next_id += 1;

        var proc = try self.allocator.create(Process);
        errdefer self.allocator.destroy(proc);

        // Init child struct
        proc.id = id;
        proc.child = std.process.Child.init(argv, self.allocator);
        proc.child.stdin_behavior = .Pipe;
        proc.child.stdout_behavior = .Pipe;
        proc.child.stderr_behavior = .Pipe;

        try proc.child.spawn(); // this creates the pipes

        // Store FDs for polling
        proc.stdout_fd = if (proc.child.stdout) |f| f.handle else null;
        proc.stderr_fd = if (proc.child.stderr) |f| f.handle else null;
        proc.stdin_fd = if (proc.child.stdin) |f| f.handle else null;

        // Set non-blocking mode for reading FDs?
        // It's good practice for non-blocking event loops.
        // But std.io.poll usually handles this. We'll rely on poll functionality.

        try self.processes.put(id, proc);
        return id;
    }

    /// Sends data to the process's standard input.
    pub fn send(self: *ProcessManager, id: i64, data: []const u8) !void {
        const proc = self.processes.get(id) orelse return error.ProcessNotFound;
        if (proc.child.stdin) |*stdin| {
            try stdin.writeAll(data);
        } else {
            return error.NoStdin;
        }
    }

    /// Terminates the process with the given ID.
    pub fn kill(self: *ProcessManager, id: i64) !void {
        if (self.processes.fetchRemove(id)) |kv| {
            const proc = kv.value;
            defer self.allocator.destroy(proc);
            proc.deinit();
        } else {
            return error.ProcessNotFound;
        }
    }

    /// Result of a polling operation.
    pub const PollResult = struct {
        proc_id: i64,
        stream: StreamType,
        data: []u8, // Owned by caller
    };

    /// Waits for output from any managed process.
    /// Returns an optional PollResult containing read data.
    /// If timeout_ms is 0, returns immediately.
    /// If timeout_ms is null, waits indefinitely? (Lets avoid indefinite blocking for now)
    /// NOT IMPLEMENTED PROPERLY YET (Placeholder logic)
    pub fn pollAny(self: *ProcessManager, timeout_ms: i32) !?PollResult {
        // Rebuild pollfd array
        self.poll_fds.clearRetainingCapacity();
        self.poll_map.clearRetainingCapacity();

        var it = self.processes.iterator();
        while (it.next()) |entry| {
            const proc = entry.value_ptr.*;
            if (proc.stdout_fd) |fd| {
                try self.poll_fds.append(.{ .fd = fd, .events = Posix.POLL.IN, .revents = 0 });
                try self.poll_map.append(.{ .id = proc.id, .type = .stdout });
            }
            if (proc.stderr_fd) |fd| {
                try self.poll_fds.append(.{ .fd = fd, .events = Posix.POLL.IN, .revents = 0 });
                try self.poll_map.append(.{ .id = proc.id, .type = .stderr });
            }
        }

        if (self.poll_fds.items.len == 0) {
            if (timeout_ms > 0) std.time.sleep(@intCast(timeout_ms * 1_000_000));
            return null;
        }

        const count = try Posix.poll(self.poll_fds.items, timeout_ms);
        if (count == 0) return null;

        // Check which one is ready
        for (self.poll_fds.items, 0..) |pfd, i| {
            if ((pfd.revents & Posix.POLL.IN) != 0) {
                const info = self.poll_map.items[i];
                // Read data
                const buf = try self.allocator.alloc(u8, self.max_read_size);
                const bytes_read = Posix.read(pfd.fd, buf) catch |err| {
                    self.allocator.free(buf);
                    return err;
                };

                if (bytes_read == 0) {
                    // EOF handling
                    // If read returns 0, the pipe is closed.
                    // We should probably mark this FD as closed in the process struct so we don't poll it again.
                    if (self.processes.get(info.id)) |proc| {
                        if (info.type == .stdout) proc.stdout_fd = null;
                        if (info.type == .stderr) proc.stderr_fd = null;
                    }
                    self.allocator.free(buf);
                    continue;
                }

                const final_buf = try self.allocator.realloc(buf, bytes_read);

                return PollResult{
                    .proc_id = info.id,
                    .stream = info.type,
                    .data = final_buf,
                };
            }
        }

        return null;
    }
};
