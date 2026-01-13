const std = @import("std");

pub const ExecResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

pub fn runProcess(allocator: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) !ExecResult {
    var child = std.process.Child.init(argv, allocator);
    child.cwd = cwd;
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    var stdout = std.ArrayListUnmanaged(u8){};
    defer stdout.deinit(allocator);
    var stderr = std.ArrayListUnmanaged(u8){};
    defer stderr.deinit(allocator);

    try child.collectOutput(allocator, &stdout, &stderr, 10 * 1024 * 1024); // 10MB limit

    const term = try child.wait();

    // Convert exit code
    const code: u8 = switch (term) {
        .Exited => |c| c,
        else => 1, // Signal or other error
    };

    return ExecResult{
        .stdout = try stdout.toOwnedSlice(allocator),
        .stderr = try stderr.toOwnedSlice(allocator),
        .exit_code = code,
    };
}
