const std = @import("std");
const Game = @import("game.zig");

pub fn main() !void {
    var game = try Game.init();
    defer game.deinit();
    try game.run();
}
