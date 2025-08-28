const sdl = @import("sdl");
const key_store = @import("data/keystore.zig");

buttons: key_store.KeyStore(@TypeOf(sdl.BUTTON_LEFT), 4, 0) = .{},

x_screen: f32 = 0,
y_screen: f32 = 0,
x_norm: f32 = 0,
y_norm: f32 = 0,
dx: f32 = 0,
dy: f32 = 0,
wheel: i32 = 0,

pub fn reset(mouse: *@This()) void {
    mouse.buttons.reset();
    mouse.wheel = 0;
}
