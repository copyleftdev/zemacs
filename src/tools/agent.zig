const std = @import("std");
const json = std.json;

pub const AgentThought = struct {
    pub const name = "agent.thought";
    pub const description = "Records a chain-of-thought step. Use this to think out loud.";

    pub const Args = struct {
        thought: []const u8,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        // In a real implementation, this might emit a specialized JSON-RPC notification
        // or write to a structured log. For now, we echo it back so the client
        // can display it in a 'Thought' buffer.
        const msg = try std.fmt.allocPrint(allocator, "Thinking: {s}", .{args.thought});
        return json.Value{ .string = msg };
    }
};

pub const AgentPlan = struct {
    pub const name = "agent.plan";
    pub const description = "Reads or updates the current plan (PLAN.md).";

    pub const Args = struct {
        // If content is null, we read. If present, we overwrite/update.
        content: ?[]const u8 = null,
    };

    pub fn run(allocator: std.mem.Allocator, args: Args) !json.Value {
        const plan_path = "PLAN.md";

        if (args.content) |new_content| {
            // Write/Update
            const file = try std.fs.cwd().createFile(plan_path, .{});
            defer file.close();
            try file.writeAll(new_content);
            return json.Value{ .string = "Plan updated." };
        } else {
            // Read
            const file = std.fs.cwd().openFile(plan_path, .{}) catch |err| {
                if (err == error.FileNotFound) {
                    return json.Value{ .string = "No plan exists yet. Create one by calling agent.plan with content." };
                }
                return err;
            };
            defer file.close();

            const content = try file.readToEndAlloc(allocator, 1 * 1024 * 1024); // 1MB max
            return json.Value{ .string = content };
        }
    }
};
