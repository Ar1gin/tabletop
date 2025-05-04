const std = @import("std");
const utils = @import("utils.zig");
const Resource = @This();

/// Resource data
pointer: *anyopaque,
/// Pointer to the memory allocted for this resource
buffer: []u8,
alignment: u29,
hash: utils.Hash,

pub fn deinit(self: *Resource, alloc: std.mem.Allocator) void {
    alloc.free(self.buffer);
}
