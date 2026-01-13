const std = @import("std");
const json = std.json;
const LspClient = @import("../core/lsp_client.zig").LspClient;

// Global LSP client state (not thread safe, but we are single threaded)
var global_client: ?*LspClient = null;

pub const LspManage = struct {
    pub const name = "lsp.manage";
    pub const description = "Starts the LSP server (e.g. mock_lsp, zls, gopls)";

    pub const Args = struct {
        command: []const u8,
        args: ?[]const []const u8 = null,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        if (global_client) |c| {
            c.deinit();
            global_client = null;
        }

        var cmd_list = std.ArrayList([]const u8).init(allocator);
        try cmd_list.append(args.command);
        if (args.args) |a| {
            try cmd_list.appendSlice(a);
        }

        global_client = try LspClient.init(allocator, try cmd_list.toOwnedSlice());

        // Initial handshake?
        // For 'mock_lsp', it handles requests immediately.
        // Real LSPs need 'initialize' request.
        // We'll send it automatically.
        _ = try global_client.?.sendRequest("initialize", .{
            .capabilities = .{},
            .processId = std.os.linux.getpid(),
            .rootUri = "file:///home/ops/Project/zemacs", // hardcoded root for MVP
        });

        return json.Value{ .string = "LSP started and initialized." };
    }
};

pub const LspHover = struct {
    pub const name = "lsp.hover";
    pub const description = "Gets hover information for a position";

    pub const Args = struct {
        file: []const u8,
        line: i32,
        col: i32,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        _ = allocator;
        if (global_client == null) return json.Value{ .string = "LSP not running. Call lsp.manage first." };

        const params = .{
            .textDocument = .{ .uri = args.file }, // Simplified URI handling
            .position = .{ .line = args.line, .character = args.col },
        };

        return try global_client.?.sendRequest("textDocument/hover", params);
    }
};

pub const LspDefinition = struct {
    pub const name = "lsp.definition";
    pub const description = "Go to definition";

    pub const Args = struct {
        file: []const u8,
        line: i32,
        col: i32,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        _ = allocator;
        if (global_client == null) return json.Value{ .string = "LSP not running. Call lsp.manage first." };

        const params = .{
            .textDocument = .{ .uri = args.file },
            .position = .{ .line = args.line, .character = args.col },
        };

        return try global_client.?.sendRequest("textDocument/definition", params);
    }
};
