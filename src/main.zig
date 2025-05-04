const std = @import("std");
const sdl = @import("sdl");
const Game = @import("game.zig");

pub fn runGame() !void {
    var game = try Game.init();
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
