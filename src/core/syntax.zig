const std = @import("std");
const GapBuffer = @import("buffer.zig").GapBuffer;
const Allocator = std.mem.Allocator;

pub const SyntaxClass = enum {
    Whitespace,
    Word,
    Symbol,
    OpenParen,
    CloseParen,
    StringQuote,
    Escape,
    CommentStart,
    CommentEnd,
    Punctuation,
};

pub const SyntaxTable = struct {
    allocator: Allocator,
    classes: [256]SyntaxClass,
    matching_pairs: std.AutoHashMap(u8, u8),

    pub fn init(allocator: Allocator) SyntaxTable {
        return .{
            .allocator = allocator,
            .classes = [_]SyntaxClass{.Punctuation} ** 256,
            .matching_pairs = std.AutoHashMap(u8, u8).init(allocator),
        };
    }

    pub fn deinit(self: *SyntaxTable) void {
        self.matching_pairs.deinit();
    }

    pub fn setClass(self: *SyntaxTable, char: u8, class: SyntaxClass) void {
        self.classes[char] = class;
    }

    pub fn setPair(self: *SyntaxTable, open: u8, close: u8) !void {
        try self.matching_pairs.put(open, close);
        self.classes[open] = .OpenParen;
        self.classes[close] = .CloseParen;
    }

    pub fn getClass(self: SyntaxTable, char: u8) SyntaxClass {
        return self.classes[char];
    }

    pub fn initStandard(allocator: Allocator) !SyntaxTable {
        var self = SyntaxTable.init(allocator);

        // Whitespace
        self.setClass(' ', .Whitespace);
        self.setClass('\t', .Whitespace);
        self.setClass('\n', .Whitespace);
        self.setClass('\r', .Whitespace);

        // Words
        var c: u8 = 'a';
        while (c <= 'z') : (c += 1) self.setClass(c, .Word);
        c = 'A';
        while (c <= 'Z') : (c += 1) self.setClass(c, .Word);
        c = '0';
        while (c <= '9') : (c += 1) self.setClass(c, .Word);

        // Symbols
        self.setClass('_', .Symbol);
        self.setClass('-', .Symbol);

        // Strings and Escapes
        self.setClass('"', .StringQuote);
        self.setClass('\\', .Escape);

        // Comments
        self.setClass(';', .CommentStart);

        // Pairs
        try self.setPair('(', ')');
        try self.setPair('[', ']');
        try self.setPair('{', '}');

        return self;
    }
};

fn skipWhitespace(buffer: GapBuffer, table: *const SyntaxTable, start_pos: usize) usize {
    var pos = start_pos;
    const len = buffer.len();
    while (pos < len) {
        const c = buffer.get(pos);
        const class = table.getClass(c);
        switch (class) {
            .Whitespace => {
                pos += 1;
            },
            .CommentStart => {
                pos += 1;
                while (pos < len) {
                    if (buffer.get(pos) == '\n') {
                        pos += 1;
                        break;
                    }
                    pos += 1;
                }
            },
            else => return pos,
        }
    }
    return pos;
}

pub fn scanSexp(buffer: GapBuffer, table: *const SyntaxTable, start_pos: usize) !usize {
    const len = buffer.len();

    // 1. Skip whitespace
    var pos = skipWhitespace(buffer, table, start_pos);
    if (pos >= len) return error.EndOfBuffer;

    // 2. Scan one sexp
    const c = buffer.get(pos);
    const class = table.getClass(c);

    switch (class) {
        .OpenParen => {
            const expected_close = table.matching_pairs.get(c) orelse return error.InvalidSyntax;
            pos += 1; // Consume open

            while (pos < len) {
                // Peek next token start
                const next = skipWhitespace(buffer, table, pos);
                if (next >= len) return error.UnbalancedParentheses;

                const nc = buffer.get(next);
                if (nc == expected_close) {
                    return next + 1; // Found matching close
                }

                if (table.getClass(nc) == .CloseParen) {
                    return error.MismatchedParentheses; // Found WRONG closer
                }

                // Recurse to consume inner sexp
                pos = try scanSexp(buffer, table, next);
            }
            return error.UnbalancedParentheses;
        },
        .StringQuote => {
            pos += 1; // Open quote
            while (pos < len) {
                const str_c = buffer.get(pos);
                if (table.getClass(str_c) == .Escape) {
                    pos += 2;
                } else if (table.getClass(str_c) == .StringQuote) {
                    pos += 1;
                    return pos;
                } else {
                    pos += 1;
                }
            }
            return error.UnbalancedString;
        },
        .CloseParen => {
            return error.UnexpectedCloseParen;
        },
        .Word, .Symbol, .Punctuation, .Escape => {
            // Consume atom
            while (pos < len) {
                const next_c = buffer.get(pos);
                const next_class = table.getClass(next_c);
                switch (next_class) {
                    .Whitespace, .OpenParen, .CloseParen, .StringQuote, .CommentStart => return pos,
                    else => pos += 1,
                }
            }
            return pos;
        },
        .CommentEnd => {
            pos += 1;
            return pos;
        },
        else => {
            pos += 1;
            return pos;
        },
    }
}

pub fn scanSexpN(buffer: GapBuffer, table: *const SyntaxTable, start_pos: usize, count: isize) !usize {
    var pos = start_pos;
    var i: isize = 0;
    if (count >= 0) {
        while (i < count) : (i += 1) {
            pos = try scanSexp(buffer, table, pos);
        }
    } else {
        return error.NotImplemented; // Backward scan todo
    }
    return pos;
}
