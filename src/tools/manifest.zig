const std = @import("std");
const json = std.json;
const schema = @import("../mcp/schema.zig");
const protocol = @import("../mcp/protocol.zig");

const fs_tools = @import("../tools/fs.zig");
const search_tools = @import("../tools/search.zig");
const agent_tools = @import("../tools/agent.zig");
const lsp_tools = @import("../tools/lsp.zig");
const exec_tools = @import("../tools/exec.zig");
const git_tools = @import("../tools/git.zig");
const lifecycle_tools = @import("../tools/lifecycle.zig");
const ui_tools = @import("../tools/ui.zig");
const repl_tools = @import("../tools/repl.zig");

// Sample tool implementation for testing
const EchoTool = struct {
    pub const name = "echo";
    pub const description = "Echoes back the input";

    pub const Args = struct {
        message: []const u8,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        const msg = try allocator.dupe(u8, args.message);
        return json.Value{ .string = msg };
    }
};

// Registry of all tools
// In a real app, this might use a more dynamic discovery or a build-generated list.
// For now, we list them explicitly.
pub const ToolRegistry = struct {
    pub const tools = .{
        EchoTool,
        fs_tools.FsRead,
        fs_tools.FsWrite,
        fs_tools.FsProposeWrite,
        search_tools.ProjectTree,
        search_tools.SearchFiles,
        search_tools.SearchGrep,
        agent_tools.AgentThought,
        agent_tools.AgentPlan,
        lsp_tools.LspManage,
        lsp_tools.LspHover,
        lsp_tools.LspDefinition,
        exec_tools.ExecRun,
        git_tools.GitStatus,
        git_tools.GitDiff,
        lifecycle_tools.ZemacsHealth,
        lifecycle_tools.ZemacsStatus,
        ui_tools.UiAskUser,
        repl_tools.ReplStart,
        repl_tools.ReplEval,
        repl_tools.ReplRead,
        repl_tools.ReplKill,
    };

    /// Generates the MCP ListToolsResult
    pub fn listTools(allocator: std.mem.Allocator) !protocol.ListToolsResult {
        var tool_list = std.ArrayList(protocol.Tool).init(allocator);

        inline for (tools) |T| {
            const s = try schema.generateSchema(allocator, T.Args);
            try tool_list.append(protocol.Tool{
                .name = T.name,
                .description = T.description,
                .inputSchema = s,
            });
        }

        return protocol.ListToolsResult{
            .tools = try tool_list.toOwnedSlice(),
        };
    }

    // Dispatch logic will go here later
    pub fn execute(allocator: std.mem.Allocator, name: []const u8, args_json: ?json.Value) !json.Value {
        inline for (tools) |T| {
            if (std.mem.eql(u8, name, T.name)) {
                if (args_json) |aj| {
                    // Robust way: stringify the value, then parse into T.Args
                    const s = try std.json.stringifyAlloc(allocator, aj, .{});
                    defer allocator.free(s);

                    const parsed = try std.json.parseFromSlice(T.Args, allocator, s, .{ .ignore_unknown_fields = true });
                    defer parsed.deinit();

                    return T.run(allocator, parsed.value);
                } else {
                    return error.InvalidParams;
                }
            }
        }
        return error.MethodNotFound;
    }
};
