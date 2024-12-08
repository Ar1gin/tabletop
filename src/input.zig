const game = @import("game.zig");
const touch = @import("touch.zig");
const mouse = @import("mouse.zig");
const std = @import("std");

const FIELD_SIZE: f32 = 16.0;
const DRAG_RADIUS: f32 = 1.5;
const DROP_RADIUS: f32 = 0.5;

input_type: InputType,

const InputType = union(enum) {
    touch: touch.TouchState,
    // mouse: mouse.MouseState,
};

// All coordinates are in screen space
pub const InputResponse = union(enum) {
    none,
    click: struct { x: f32, y: f32, t: bool },
    start_drag: struct { x: f32, y: f32 },
    drag: struct { x: f32, y: f32, r: f32 },
    stop_drag,
    start_pan,
    pan: struct { x: f32, y: f32, z: f32, r: f32 },
    stop_pan,
};

const Self = @This();
pub fn default() Self {
    return Self{
        .input_type = InputType{ .touch = touch.TouchState{ .none = 0.0 } },
    };
}

pub fn update(self: *Self, state: *const game.GameState, delta: f32) void {
    const response = switch (self.input_type) {
        InputType.touch => |*touch_state| touch.update(touch_state, &state.camera, delta),
        // InputType.mouse => |*mouse_state| mouse.update(mouse_state, state, delta),
    };
    if (response != InputResponse.none) {
        std.debug.print("{any}\n", .{response});
    }
    // switch (response) {
    //     .none => {},
    //     .click => |click| {},
    //     .start_drag => |start_drag| {},
    //     .drag => |drag| {},
    //     .stop_drag => {},
    //     .start_pan => {},
    //     .pan => |pan| {},
    //     .stop_pan => {},
    // }
}

