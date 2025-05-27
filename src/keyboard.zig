const sdl = @import("sdl");

const BUFFER_SIZE = 16;
const ZERO = sdl.SCANCODE_UNKNOWN;

just_pressed: [BUFFER_SIZE]sdl.Scancode = .{ZERO} ** BUFFER_SIZE,
pressed: [BUFFER_SIZE]sdl.Scancode = .{ZERO} ** BUFFER_SIZE,
just_released: [BUFFER_SIZE]sdl.Scancode = .{ZERO} ** BUFFER_SIZE,

const Self = @This();
pub fn reset(self: *Self) void {
    self.just_pressed = .{ZERO} ** BUFFER_SIZE;
    self.just_released = .{ZERO} ** BUFFER_SIZE;
}
pub fn press(self: *Self, code: sdl.Scancode) void {
    for (self.pressed) |pressed| {
        if (pressed == code) return;
    }
    for (&self.pressed) |*pressed| {
        if (pressed.* == ZERO) {
            pressed.* = code;
            break;
        }
    }
    for (self.just_pressed) |just_pressed| {
        if (just_pressed == code) return;
    }
    for (&self.just_pressed) |*just_pressed| {
        if (just_pressed.* == ZERO) {
            just_pressed.* = code;
            break;
        }
    }
}
pub fn release(self: *Self, code: sdl.Scancode) void {
    for (&self.pressed) |*pressed| {
        if (pressed.* == code) {
            pressed.* = ZERO;
            break;
        }
    }
    for (self.just_released) |just_released| {
        if (just_released == code) return;
    }
    for (&self.just_released) |*just_released| {
        if (just_released.* == ZERO) {
            just_released.* = code;
            break;
        }
    }
}
pub fn is_just_pressed(self: *Self, code: sdl.Scancode) bool {
    for (self.just_pressed) |just_pressed| {
        if (just_pressed == code) return true;
    }
    return false;
}
pub fn is_pressed(self: *Self, code: sdl.Scancode) bool {
    for (self.pressed) |pressed| {
        if (pressed == code) return true;
    }
    return false;
}
pub fn is_just_released(self: *Self, code: sdl.Scancode) bool {
    for (self.just_released) |just_released| {
        if (just_released == code) return true;
    }
    return false;
}
