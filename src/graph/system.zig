const std = @import("std");
const utils = @import("utils.zig");
const Controller = @import("controller.zig");

function_runner: *const fn ([]const *anyopaque) void,
requested_types: []const Request,
requires_dud: ?Dud.Id,
submit_dud: ?Dud.Id,

pub const Dud = struct {
    pub const Id = u16;

    required_count: usize = 0,
};

pub const Request = union(enum) {
    resource: utils.Hash,
    controller: void,
    // TODO:
    // - Params
};

const Self = @This();
pub fn fromFunction(comptime function: anytype, alloc: std.mem.Allocator) !Self {
    utils.validateSystem(function);

    var requests: [@typeInfo(@TypeOf(function)).@"fn".params.len]Request = undefined;
    inline for (0.., @typeInfo(@TypeOf(function)).@"fn".params) |i, param| {
        switch (@typeInfo(param.type.?).pointer.child) {
            Controller => requests[i] = .controller,
            else => |resource_type| requests[i] = .{ .resource = utils.hashType(resource_type) },
        }
    }

    return Self{
        .requested_types = try alloc.dupe(Request, &requests),
        .function_runner = utils.generateRunner(function),
        .requires_dud = null,
        .submit_dud = null,
    };
}

pub fn deinit(self: *const Self, alloc: std.mem.Allocator) void {
    alloc.free(self.requested_types);
}
