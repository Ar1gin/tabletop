const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");
const Game = @import("game.zig");

pub fn main() void {
    var allocator = switch (builtin.mode) {
        .ReleaseSafe, .Debug => std.heap.DebugAllocator(.{}).init,
        .ReleaseFast => std.heap.smp_allocator,
        .ReleaseSmall => std.heap.c_allocator,
    };
    defer switch (builtin.mode) {
        .ReleaseSafe, .Debug => std.debug.assert(allocator.deinit() == .ok),
        else => {},
    };

    Game.init(
        switch (builtin.mode) {
            .ReleaseSafe, .Debug => allocator.allocator(),
            .ReleaseFast => allocator,
            .ReleaseSmall => allocator,
        },
    );
    defer Game.deinit();
    Game.run();
}
