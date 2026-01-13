const std = @import("std");
const json = std.json;

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

const ReplSession = struct {
    id: i64,
    child: std.process.Child,
    allocator: std.mem.Allocator,
    stdout_buf: OutputBuffer,
    stderr_buf: OutputBuffer,

    pub fn init(allocator: std.mem.Allocator, id: i64, argv: []const []const u8) !*ReplSession {
        var self = try allocator.create(ReplSession);
        self.id = id;
        self.allocator = allocator;
        self.stdout_buf = OutputBuffer.init(allocator);
        self.stderr_buf = OutputBuffer.init(allocator);

        self.child = std.process.Child.init(argv, allocator);
        self.child.stdin_behavior = .Pipe;
        self.child.stdout_behavior = .Pipe;
        self.child.stderr_behavior = .Pipe;

        try self.child.spawn();

        const t1 = try std.Thread.spawn(.{}, readerLoop, .{ self.child.stdout.?.reader(), &self.stdout_buf });
        t1.detach();

        const t2 = try std.Thread.spawn(.{}, readerLoop, .{ self.child.stderr.?.reader(), &self.stderr_buf });
        t2.detach();

        return self;
    }

    pub fn deinit(self: *ReplSession) void {
        _ = self.child.kill() catch {};
        self.stdout_buf.deinit();
        self.stderr_buf.deinit();
        self.allocator.destroy(self);
    }

    fn readerLoop(reader: anytype, buf: *OutputBuffer) !void {
        var tmp: [1024]u8 = undefined;
        while (true) {
            const bytes_read = reader.read(&tmp) catch break;
            if (bytes_read == 0) break; // EOF
            buf.append(tmp[0..bytes_read]) catch break;
        }
    }
};

pub const ReplManager = struct {
    allocator: std.mem.Allocator,
    sessions: std.AutoHashMap(i64, *ReplSession),
    next_id: std.atomic.Value(i64),

    pub fn init(allocator: std.mem.Allocator) ReplManager {
        return .{
            .allocator = allocator,
            .sessions = std.AutoHashMap(i64, *ReplSession).init(allocator),
            .next_id = std.atomic.Value(i64).init(1),
        };
    }

    pub fn deinit(self: *ReplManager) void {
        var it = self.sessions.valueIterator();
        while (it.next()) |session| {
            session.*.deinit();
        }
        self.sessions.deinit();
    }

    pub fn start(self: *ReplManager, argv: []const []const u8) !i64 {
        const id = self.next_id.fetchAdd(1, .monotonic);
        const session = try ReplSession.init(self.allocator, id, argv);
        try self.sessions.put(id, session);
        return id;
    }

    pub fn eval(self: *ReplManager, id: i64, code: []const u8) !void {
        const session = self.sessions.get(id) orelse return error.SessionNotFound;
        const stdin = session.child.stdin.?.writer();
        try stdin.print("{s}\n", .{code});
    }

    pub fn readOutput(self: *ReplManager, id: i64) !struct { stdout: []u8, stderr: []u8 } {
        const session = self.sessions.get(id) orelse return error.SessionNotFound;
        const out = try session.stdout_buf.readAndClear();
        const err = try session.stderr_buf.readAndClear();
        return .{ .stdout = out, .stderr = err };
    }

    pub fn kill(self: *ReplManager, id: i64) !void {
        if (self.sessions.fetchRemove(id)) |kv| {
            kv.value.deinit();
        } else {
            return error.SessionNotFound;
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
