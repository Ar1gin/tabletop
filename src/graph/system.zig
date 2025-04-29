const std = @import("std");
const utils = @import("utils.zig");
const Controller = @import("resource.zig").Controller;

function_runner: *const fn ([]const *anyopaque) void,
requested_types: []const Request,

pub const Request = union(enum) {
    resource: utils.Hash,
    controller: void,
    // TODO:
    // - Params
};

const Self = @This();
pub fn from_function(comptime function: anytype, alloc: std.mem.Allocator) !Self {
    utils.validate_system(function);

    var requests: [@typeInfo(@TypeOf(function)).Fn.params.len]Request = undefined;
    inline for (0.., @typeInfo(@TypeOf(function)).Fn.params) |i, param| {
        switch (@typeInfo(param.type.?).Pointer.child) {
            Controller => requests[i] = .controller,
            else => |resource_type| requests[i] = .{ .resource = utils.hash_type(resource_type) },
        }
    }

    return Self{
        .requested_types = try alloc.dupe(Request, &requests),
        .function_runner = utils.generate_runner(function),
    };
}

pub fn deinit(self: *const Self, alloc: std.mem.Allocator) void {
    alloc.free(self.requested_types);
}
