pub fn KeyStore(comptime key_type: type, comptime buf_size: usize, comptime zero: key_type) type {
    return struct {
        just_pressed: [buf_size]key_type = .{zero} ** buf_size,
        pressed: [buf_size]key_type = .{zero} ** buf_size,
        just_released: [buf_size]key_type = .{zero} ** buf_size,

        const Self = @This();
        pub fn reset(self: *Self) void {
            self.just_pressed = .{zero} ** buf_size;
            self.just_released = .{zero} ** buf_size;
        }
        pub fn press(self: *Self, code: key_type) void {
            for (self.pressed) |pressed| {
                if (pressed == code) return;
            }
            for (&self.pressed) |*pressed| {
                if (pressed.* == zero) {
                    pressed.* = code;
                    break;
                }
            }
            for (self.just_pressed) |just_pressed| {
                if (just_pressed == code) return;
            }
            for (&self.just_pressed) |*just_pressed| {
                if (just_pressed.* == zero) {
                    just_pressed.* = code;
                    break;
                }
            }
        }
        pub fn release(self: *Self, code: key_type) void {
            for (&self.pressed) |*pressed| {
                if (pressed.* == code) {
                    pressed.* = zero;
                    break;
                }
            }
            for (self.just_released) |just_released| {
                if (just_released == code) return;
            }
            for (&self.just_released) |*just_released| {
                if (just_released.* == zero) {
                    just_released.* = code;
                    break;
                }
            }
        }
        pub fn is_just_pressed(self: *Self, code: key_type) bool {
            for (self.just_pressed) |just_pressed| {
                if (just_pressed == code) return true;
            }
            return false;
        }
        pub fn is_pressed(self: *Self, code: key_type) bool {
            for (self.pressed) |pressed| {
                if (pressed == code) return true;
            }
            return false;
        }
        pub fn is_just_released(self: *Self, code: key_type) bool {
            for (self.just_released) |just_released| {
                if (just_released == code) return true;
            }
            return false;
        }
    };
}
