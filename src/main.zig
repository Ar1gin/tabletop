const std = @import("std");
const rl = @import("raylib");
const GameState = @import("game.zig").GameState;
const Config = @import("config.zig");
const Net = @import("net.zig");

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

    const config = try Config.parse(alloc, "assets/debug_config.json");
    defer config.deinit();

    var net = try Net.init(alloc, &config.value);
    defer net.deinit();

    var game_state = try GameState.init(
        alloc,
        &config.value,
        net.items.items,
    );
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
