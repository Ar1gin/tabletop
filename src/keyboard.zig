const sdl = @import("sdl");
const key_store = @import("data/keystore.zig");

keys: key_store.KeyStore(sdl.Scancode, 16, sdl.SCANCODE_UNKNOWN) = .{},
