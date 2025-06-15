const std = @import("std");
const utils = @import("utils.zig");
const Controller = @import("controller.zig");

function_runner: *const fn ([]const *anyopaque) void,
requested_types: []const utils.SystemRequest,
requires_dud: ?Dud.Id,
submit_dud: ?Dud.Id,
label: []const u8,

pub const Dud = struct {
    pub const Id = usize;

    required_count: u16 = 0,
};
