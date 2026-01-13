const std = @import("std");
const json = std.json;

/// Generates a JSON Schema object for a given Zig type (assumed to be a Struct representing arguments).
/// This implementation creates a generic JSON Value tree that can be stringified.
pub fn generateSchema(allocator: std.mem.Allocator, comptime T: type) !json.Value {
    const info = @typeInfo(T);
    switch (info) {
        .@"struct" => |struct_info| {
            var properties = std.json.ObjectMap.init(allocator);
            var required = std.ArrayList(json.Value).init(allocator);

            inline for (struct_info.fields) |field| {
                const field_schema = try typeToSchema(allocator, field.type);
                try properties.put(field.name, field_schema);

                // If it's not optional, it's required
                if (!isOptional(field.type)) {
                    try required.append(json.Value{ .string = field.name });
                }
            }

            var root_map = std.json.ObjectMap.init(allocator);
            try root_map.put("type", json.Value{ .string = "object" });
            try root_map.put("properties", json.Value{ .object = properties });
            try root_map.put("required", json.Value{ .array = required });

            return json.Value{ .object = root_map };
        },
        else => {
            // fast-fail for now, only structs allowed for top-level args
            @compileError("Tool Arguments must be a Struct");
        },
    }
}

fn typeToSchema(allocator: std.mem.Allocator, comptime T: type) !json.Value {
    const info = @typeInfo(T);
    var map = std.json.ObjectMap.init(allocator);

    switch (info) {
        .bool => {
            try map.put("type", json.Value{ .string = "boolean" });
        },
        .int, .comptime_int => {
            try map.put("type", json.Value{ .string = "integer" });
        },
        .float, .comptime_float => {
            try map.put("type", json.Value{ .string = "number" });
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                try map.put("type", json.Value{ .string = "string" });
            } else if (ptr.size == .slice) {
                try map.put("type", json.Value{ .string = "array" });
                const item_schema = try typeToSchema(allocator, ptr.child);
                try map.put("items", item_schema);
            } else {
                // assume const string for now or fail
                try map.put("type", json.Value{ .string = "string" });
            }
        },
        .array => |arr| {
            if (arr.child == u8) {
                try map.put("type", json.Value{ .string = "string" });
            } else {
                try map.put("type", json.Value{ .string = "array" });
                const item_schema = try typeToSchema(allocator, arr.child);
                try map.put("items", item_schema);
            }
        },
        .optional => |opt| {
            // Recursively get the child type, but don't mark as required (handled in parent).
            return typeToSchema(allocator, opt.child);
        },
        .@"struct" => {
            // Nested struct
            return generateSchema(allocator, T);
        },
        else => {
            // Fallback
            try map.put("type", json.Value{ .string = "string" });
        },
    }
    return json.Value{ .object = map };
}

fn isOptional(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .optional => true,
        else => false,
    };
}
