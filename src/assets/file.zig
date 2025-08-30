const std = @import("std");
const Assets = @import("../assets.zig");

bytes: []u8,

pub fn load(path: []const u8, alloc: std.mem.Allocator) Assets.LoadError!@This() {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return .{ .bytes = try file.readToEndAlloc(alloc, std.math.maxInt(i32)) };
}

pub fn unload(self: @This(), alloc: std.mem.Allocator) void {
    alloc.free(self.bytes);
}
