const std = @import("std");

pub const ZemacsError = error{
    IoError,
    OutOfMemory,
    JsonParseError,
    MethodNotFound,
    InvalidParams,
    InternalError,
};

pub const LogLevel = enum {
    Debug,
    Info,
    Warning,
    Error,
};
