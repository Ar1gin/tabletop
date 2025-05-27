const sdl = @import("sdl");
const key_store = @import("data/keystore.zig");

buttons: key_store.KeyStore(@TypeOf(sdl.BUTTON_LEFT), 4, 0),

x: f32,
y: f32,
dx: f32,
dy: f32,
