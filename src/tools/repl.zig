const std = @import("std");
const json = std.json;
const ProcessManager = @import("../core/process.zig").ProcessManager;

// Thread-safe buffer for REPL output
const OutputBuffer = struct {
    mutex: std.Thread.Mutex,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) OutputBuffer {
        return .{
            .mutex = .{},
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *OutputBuffer) void {
        self.buffer.deinit();
    }

    pub fn append(self: *OutputBuffer, data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.buffer.appendSlice(data);
    }

    pub fn readAndClear(self: *OutputBuffer) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        const result = try self.buffer.toOwnedSlice();
        return result;
    }
};

const SessionBuffers = struct {
    stdout: OutputBuffer,
    stderr: OutputBuffer,

    pub fn init(allocator: std.mem.Allocator) SessionBuffers {
        return .{
            .stdout = OutputBuffer.init(allocator),
            .stderr = OutputBuffer.init(allocator),
        };
    }

    pub fn deinit(self: *SessionBuffers) void {
        self.stdout.deinit();
        self.stderr.deinit();
    }
};

pub const ReplManager = struct {
    allocator: std.mem.Allocator,
    process_manager: ProcessManager,
    buffers: std.AutoHashMap(i64, *SessionBuffers),

    // Background polling thread
    poll_thread: ?std.Thread = null,
    transport_mutex: std.Thread.Mutex = .{}, // Protects shared state if needed
    running: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator) ReplManager {
        // Initialize as undefined first to set fields?
        // No, struct literal.
        const pm = ProcessManager.init(allocator);

        const self = ReplManager{
            .allocator = allocator,
            .process_manager = pm,
            .buffers = std.AutoHashMap(i64, *SessionBuffers).init(allocator),
            .running = std.atomic.Value(bool).init(true),
        };

        // We need to start the thread, but `self` is currently a value on stack/return.
        // The caller typically puts this on heap or keeps it stable?
        // `main.zig` does: `repl.global_manager = repl.ReplManager.init(allocator);`
        // `global_manager` is a global variable.
        // Zig structs inits don't start threads on `self` usually if `self` moves.
        // We will start thread lazily or requiring an explicitly stored pointer?
        // We can just rely on `start()` to spawn thread if not running?
        // Or make `init` return a started manager?
        // Since `global_manager` is a var, it is stable address `&global_manager`.
        // But `init` returns a VALUE.
        // We'll require an explicit `startPolling` or start it on first process spawn.
        // But `ReplManager` needs to store `self` pointer for thread?
        // Thread needs `*ReplManager`.
        // We'll handle thread starting separately or assume pointer stability isn't needed if we pass `&process_manager` and `&buffers` (protected by mutex)?
        // `ProcessManager` is inside `ReplManager`.

        return self;
    }

    // Must be called after `global_manager` is assigned.
    pub fn startPolling(self: *ReplManager) !void {
        if (self.poll_thread != null) return;
        self.poll_thread = try std.Thread.spawn(.{}, pollLoop, .{self});
    }

    pub fn deinit(self: *ReplManager) void {
        self.running.store(false, .release);
        if (self.poll_thread) |t| t.join();

        var it = self.buffers.valueIterator();
        while (it.next()) |buf| {
            buf.*.deinit();
            self.allocator.destroy(buf.*);
        }
        self.buffers.deinit();
        self.process_manager.deinit();
    }

    fn pollLoop(self: *ReplManager) void {
        while (self.running.load(.acquire)) {
            // Poll with timeout
            const result = self.process_manager.pollAny(100) catch |err| {
                std.debug.print("Poll error: {}\n", .{err});
                std.time.sleep(100 * 1_000_000);
                continue;
            } orelse continue;

            // Handle result
            defer self.allocator.free(result.data); // data is allocated by pollAny

            self.transport_mutex.lock();
            const session_buf_opt = self.buffers.get(result.proc_id);
            self.transport_mutex.unlock();

            if (session_buf_opt) |buf_ptr| {
                switch (result.stream) {
                    .stdout => buf_ptr.stdout.append(result.data) catch {},
                    .stderr => buf_ptr.stderr.append(result.data) catch {},
                }
            }
        }
    }

    pub fn start(self: *ReplManager, argv: []const []const u8) !i64 {
        const id = try self.process_manager.spawn(argv);

        const bufs = try self.allocator.create(SessionBuffers);
        bufs.* = SessionBuffers.init(self.allocator);

        self.transport_mutex.lock();
        defer self.transport_mutex.unlock();
        try self.buffers.put(id, bufs);

        // Ensure polling is running
        if (self.poll_thread == null) {
            try self.startPolling();
        }

        return id;
    }

    pub fn eval(self: *ReplManager, id: i64, code: []const u8) !void {
        try self.process_manager.send(id, code);
        try self.process_manager.send(id, "\n"); // Add newline for typical REPL
    }

    pub fn readOutput(self: *ReplManager, id: i64) !struct { stdout: []u8, stderr: []u8 } {
        self.transport_mutex.lock();
        const buf_opt = self.buffers.get(id);
        self.transport_mutex.unlock();

        const session = buf_opt orelse return error.SessionNotFound;

        const out = try session.stdout.readAndClear();
        const err = try session.stderr.readAndClear();
        return .{ .stdout = out, .stderr = err };
    }

    pub fn kill(self: *ReplManager, id: i64) !void {
        try self.process_manager.kill(id);

        self.transport_mutex.lock();
        defer self.transport_mutex.unlock();
        if (self.buffers.fetchRemove(id)) |kv| {
            kv.value.deinit();
            self.allocator.destroy(kv.value);
        }
    }
};

// Global Instance
pub var global_manager: ReplManager = undefined;

// --- Tools ---

pub const ReplStart = struct {
    pub const name = "repl.start";
    pub const description = "Starts a new persistent REPL interaction (e.g. 'python3 -i', 'bash', 'node -i'). Returns the ID.";

    pub const Args = struct {
        command: []const u8,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        // Parse command string into slice of slices
        var argv = std.ArrayList([]const u8).init(allocator);

        // Simple tokenization by space (naive)
        var it = std.mem.tokenizeScalar(u8, args.command, ' ');
        while (it.next()) |part| {
            try argv.append(part);
        }

        // Use global manager
        const id = try global_manager.start(argv.items);
        return json.Value{ .integer = id };
    }
};

pub const ReplEval = struct {
    pub const name = "repl.eval";
    pub const description = "Evaluates code in an existing REPL session.";

    pub const Args = struct {
        id: i64,
        code: []const u8,
    };

    pub fn run(_: std.mem.Allocator, args: Args) !json.Value {
        try global_manager.eval(args.id, args.code);
        return json.Value{ .string = "Code sent to REPL." };
    }
};

pub const ReplRead = struct {
    pub const name = "repl.read";
    pub const description = "Reads pending stdout/stderr from a REPL session (non-blocking).";

    pub const Args = struct {
        id: i64,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        const out = try global_manager.readOutput(args.id);

        var map = std.json.ObjectMap.init(allocator);
        try map.put("stdout", json.Value{ .string = out.stdout });
        try map.put("stderr", json.Value{ .string = out.stderr });

        return json.Value{ .object = map };
    }
};

pub const ReplKill = struct {
    pub const name = "repl.kill";
    pub const description = "Terminates a REPL session.";

    pub const Args = struct {
        id: i64,
    };

    pub fn run(_: std.mem.Allocator, args: Args) !json.Value {
        try global_manager.kill(args.id);
        return json.Value{ .string = "REPL terminated." };
    }
};
