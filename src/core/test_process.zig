const std = @import("std");
const ProcessManager = @import("process.zig").ProcessManager;

test "ProcessManager: spawn and interact with cat" {
    const allocator = std.testing.allocator;

    var pm = ProcessManager.init(allocator);
    defer pm.deinit();

    // Spawn 'cat'
    const argv = &[_][]const u8{"cat"};
    const pid = try pm.spawn(argv);
    try std.testing.expect(pid > 0);

    // Send data
    const input = "Hello World\n";
    try pm.send(pid, input);

    // Poll for response
    // We might need to loop a few times if the OS is slow
    var found = false;
    var attempts: usize = 0;

    while (attempts < 10) : (attempts += 1) {
        if (try pm.pollAny(100)) |res| {
            defer allocator.free(res.data);

            try std.testing.expectEqual(pid, res.proc_id);
            try std.testing.expectEqualStrings(input, res.data);
            found = true;
            break;
        }
    }

    try std.testing.expect(found);
}

test "ProcessManager: spawn echo" {
    const allocator = std.testing.allocator;
    var pm = ProcessManager.init(allocator);
    defer pm.deinit();

    const argv = &[_][]const u8{ "echo", "foobar" };
    const pid = try pm.spawn(argv);

    // Poll for response
    var found = false;
    var attempts: usize = 0;
    while (attempts < 10) : (attempts += 1) {
        if (try pm.pollAny(100)) |res| {
            defer allocator.free(res.data);

            try std.testing.expectEqual(pid, res.proc_id);
            try std.testing.expectEqualStrings("foobar\n", res.data);
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "ProcessManager: kill process" {
    const allocator = std.testing.allocator;
    var pm = ProcessManager.init(allocator);
    defer pm.deinit();

    const argv = &[_][]const u8{ "sleep", "10" };
    const pid = try pm.spawn(argv);

    try pm.kill(pid);

    // Trying to kill again should fail
    try std.testing.expectError(error.ProcessNotFound, pm.kill(pid));
}
