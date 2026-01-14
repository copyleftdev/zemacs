const std = @import("std");
const GapBuffer = @import("buffer.zig").GapBuffer;
const SyntaxTable = @import("syntax.zig").SyntaxTable;
const scanSexp = @import("syntax.zig").scanSexp;
const scanSexpN = @import("syntax.zig").scanSexpN;

test "scanSexp: basic words and symbols" {
    const allocator = std.testing.allocator;
    var buf = try GapBuffer.init(allocator, 100);
    defer buf.deinit();

    var table = try SyntaxTable.initStandard(allocator);
    defer table.deinit();

    try buf.insert(0, "hello world");
    // "hello"
    try std.testing.expectEqual(@as(usize, 5), try scanSexp(buf, &table, 0));
    // "world" (skip space)
    try std.testing.expectEqual(@as(usize, 11), try scanSexp(buf, &table, 5));
}

test "scanSexp: strings" {
    const allocator = std.testing.allocator;
    var buf = try GapBuffer.init(allocator, 100);
    defer buf.deinit();
    var table = try SyntaxTable.initStandard(allocator);
    defer table.deinit();

    try buf.insert(0, "\"foo\" \"bar \\\"baz\\\"\"");

    // "foo"
    // 01234
    try std.testing.expectEqual(@as(usize, 5), try scanSexp(buf, &table, 0));

    // "bar \"baz\""
    // Starts at 6.
    // Length: 6 + 1 (") + 3 (bar) + 1 (space) + 2 (\") + 3 (baz) + 2 (\") + 1 (") = ?
    // "bar \"baz\"" is: " b a r   \ " b a z \ " "
    // Chars:
    // " (1)
    // b a r (3)
    //   (1)
    // \ " (2)
    // b a z (3)
    // \ " (2)
    // " (1)
    // Total: 13 chars.
    // End pos: 6 + 13 = 19.
    const res = try scanSexp(buf, &table, 5); // skips space at 5
    // Actually, "foo" is 0..5 (length 5).
    // Space at 5.
    // Second string starts at 6.
    // Len of second string:
    // "bar \"baz\"" -> 13 chars.
    try std.testing.expectEqual(@as(usize, 19), res);
}

test "scanSexp: nested lists" {
    const allocator = std.testing.allocator;
    var buf = try GapBuffer.init(allocator, 100);
    defer buf.deinit();
    var table = try SyntaxTable.initStandard(allocator);
    defer table.deinit();

    try buf.insert(0, "(a (b c) d)");

    // Whole list.
    // Length: 11.
    // ( a   ( b   c )   d )
    // 0 1 2 3 4 5 6 7 8 9 10
    // End is 11.
    try std.testing.expectEqual(@as(usize, 11), try scanSexp(buf, &table, 0));

    // Sub list at 3
    // (b c) -> starts at 3. Ends at 8.
    try std.testing.expectEqual(@as(usize, 8), try scanSexp(buf, &table, 3));
}

test "scanSexp: mixed delimiters" {
    const allocator = std.testing.allocator;
    var buf = try GapBuffer.init(allocator, 100);
    defer buf.deinit();
    var table = try SyntaxTable.initStandard(allocator);
    defer table.deinit();

    try buf.insert(0, "( [ a ] { b } )");
    // Should pass with recursive scanner
    try std.testing.expectEqual(@as(usize, 15), try scanSexp(buf, &table, 0));
}

test "scanSexp: mismatched delimiters" {
    const allocator = std.testing.allocator;
    var buf = try GapBuffer.init(allocator, 100);
    defer buf.deinit();
    var table = try SyntaxTable.initStandard(allocator);
    defer table.deinit();

    try buf.insert(0, "( [ a ) ]");
    // [ expects ], found )
    try std.testing.expectError(error.MismatchedParentheses, scanSexp(buf, &table, 0));
}

test "scanSexp: comments" {
    const allocator = std.testing.allocator;
    var buf = try GapBuffer.init(allocator, 100);
    defer buf.deinit();
    var table = try SyntaxTable.initStandard(allocator);
    defer table.deinit();

    try buf.insert(0, "; comment\n(foo)");
    // Should skip comment and scan (foo)
    // ; comment\n is 10 chars.
    // (foo) is 5 chars.
    // Total 15.
    try std.testing.expectEqual(@as(usize, 15), try scanSexp(buf, &table, 0));
}

test "scanSexpN: forward multiple" {
    const allocator = std.testing.allocator;
    var buf = try GapBuffer.init(allocator, 100);
    defer buf.deinit();
    var table = try SyntaxTable.initStandard(allocator);
    defer table.deinit();

    try buf.insert(0, "a b c (d e)");

    // a -> 1
    // b -> 3
    // c -> 5
    // (d e) -> 11

    // Move forward 3 sexps: a, b, c. Should end at 5.
    try std.testing.expectEqual(@as(usize, 5), try scanSexpN(buf, &table, 0, 3));

    // Move forward 4 sexps: a, b, c, (d e). Should end at 11
    try std.testing.expectEqual(@as(usize, 11), try scanSexpN(buf, &table, 0, 4));
}
