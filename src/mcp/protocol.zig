const std = @import("std");
const json = std.json;

// JSON-RPC 2.0 Constants
pub const JSONRPC_VERSION = "2.0";

pub const ErrorCode = enum(i32) {
    ParseError = -32700,
    InvalidRequest = -32600,
    MethodNotFound = -32601,
    InvalidParams = -32602,
    InternalError = -32603,
    ServerErrorStart = -32099,
    ServerErrorEnd = -32000,
    // Custom execution errors
    ToolExecutionError = -32001,
};

pub const RequestId = json.Value;

pub const JsonRpcRequest = struct {
    jsonrpc: []const u8 = JSONRPC_VERSION,
    id: RequestId,
    method: []const u8,
    params: ?json.Value = null,
};

pub const JsonRpcNotification = struct {
    jsonrpc: []const u8 = JSONRPC_VERSION,
    method: []const u8,
    params: ?json.Value = null,
};

pub const JsonRpcError = struct {
    code: i32,
    message: []const u8,
    data: ?json.Value = null,
};

pub const JsonRpcResponse = struct {
    jsonrpc: []const u8 = JSONRPC_VERSION,
    id: RequestId,
    result: ?json.Value = null,
    error_obj: ?JsonRpcError = null,

    // Custom serialization to handle the result/error mutually exclusive rule if needed,
    // but for simple structs, optional fields work fine in Zig's json stringify.
};

// Start of MCP specific structures

pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    inputSchema: json.Value,
};

pub const ListToolsResult = struct {
    tools: []const Tool,
};
