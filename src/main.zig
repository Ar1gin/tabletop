const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");
const Game = @import("game.zig");

pub fn runGame() !void {
    var allocator = switch (builtin.mode) {
        .ReleaseSafe, .Debug => std.heap.DebugAllocator(.{}).init,
        .ReleaseFast => std.heap.smp_allocator,
        .ReleaseSmall => std.heap.c_allocator,
    };
    defer switch (builtin.mode) {
        .ReleaseSafe, .Debug => std.debug.assert(allocator.deinit() == .ok),
        else => {},
    };

    var game = try Game.init(
        switch (builtin.mode) {
            .ReleaseSafe, .Debug => allocator.allocator(),
            .ReleaseFast => allocator,
            .ReleaseSmall => allocator,
        },
    );
    defer game.deinit();
    try game.run();
}

pub fn main() !void {
    runGame() catch |err| {
        switch (err) {
            error.SdlError => {
                std.debug.print("SDL Error:\n---\n{s}\n---\n", .{sdl.SDL_GetError()});
            },
            else => unreachable,
        }
        return err;
    };
}
