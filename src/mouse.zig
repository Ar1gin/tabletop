const game = @import("game.zig");

pub const MouseState = struct {};

pub fn update(mouse: *MouseState, state: *game.GameState, delta: f32) void {
    _ = mouse;
    _ = state;
    _ = delta;
}
