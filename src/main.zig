const std = @import("std");
const rl = @import("raylib");
const GameState = @import("game.zig").GameState;

pub fn main() !void {
    const screen_width = 2880 * 3 / 4;
    const screen_height = 1920 * 3 / 4;

    rl.initWindow(screen_width, screen_height, "Gaming");
    defer rl.closeWindow();
    rl.setWindowState(.{
        .vsync_hint = true,
        // TODO: Enable msaa??
        .msaa_4x_hint = true,
        .window_resizable = true,
    });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();
    var game_state = try GameState.init(alloc, "assets/debug_config.json");
    defer game_state.deinit();

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);
        game_state.update(rl.getFrameTime());
        game_state.draw();
    }
}
