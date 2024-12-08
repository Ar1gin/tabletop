const std = @import("std");
const game = @import("game.zig");
const math = @import("math.zig");
const rl = @import("raylib");
const InputResponse = @import("input.zig").InputResponse;

const DRAG_INIT_RADIUS: f32 = 64.0;
const TOUCH_RADIUS: f32 = 1.5;
const DROP_RADIUS: f32 = 0.5;

const HOLD_THRESHOLD = 0.5;
const DOUBLE_THRESHOLD: f32 = 0.2;

pub const TouchState = union(enum) {
    none: f32, // Time since last press
    pressed: struct {
        rl.Vector2, // Initial position
        f32, // Hold time
        bool, // Double
    },
    drag,
    drag_rotate: struct {
        rl.Vector2, // Previous delta
    },
    panning: struct {
        rl.Vector2, // Initial tap 1
        rl.Vector2, // Initial tap 2
        f32, // Zoom
        f32, // Rotation
        rl.Vector2, // Target
    },
    hold,
};

pub fn update(touch: *TouchState, camera: *const rl.Camera2D, delta: f32) InputResponse {
    const touch_points = rl.getTouchPointCount();
    // TODO: use `continue :blk` to rerun touch update on state change
    switch (touch.*) {
        TouchState.none => |*time| {
            switch (touch_points) {
                0 => time.* += delta,
                1 => touch.* = TouchState{ .pressed = .{ rl.getTouchPosition(0), 0.0, time.* < DOUBLE_THRESHOLD } },
                2 => {
                    touch.* = TouchState{ .panning = .{
                        rl.getTouchPosition(0),
                        rl.getTouchPosition(1),
                        camera.zoom,
                        camera.rotation,
                        camera.target,
                    } };
                    return InputResponse.start_pan;
                },
                else => {},
            }
        },
        TouchState.pressed => |*pressed| {
            switch (touch_points) {
                0 => {
                    touch.* = TouchState{ .none = 0.0 };
                    return InputResponse{ .click = .{
                        .x = pressed[0].x,
                        .y = pressed[0].y,
                        .t = false,
                    } };
                },
                1 => {
                    pressed[1] += delta;
                    if (pressed[2] or pressed[0].distanceSqr(rl.getTouchPosition(0)) >= DRAG_INIT_RADIUS) {
                        touch.* = TouchState.drag;
                        return InputResponse{ .start_drag = .{ .x = pressed[0].x, .y = pressed[0].y } };
                    } else if (pressed[1] >= HOLD_THRESHOLD) {
                        touch.* = TouchState.hold;
                        return InputResponse{ .click = .{
                            .x = pressed[0].x,
                            .y = pressed[0].y,
                            .t = true,
                        } };
                    }
                },
                2 => {
                    if (pressed[1] < HOLD_THRESHOLD) {
                        touch.* = TouchState{ .panning = .{
                            rl.getTouchPosition(0),
                            rl.getTouchPosition(1),
                            camera.zoom,
                            camera.rotation,
                            camera.target,
                        } };
                        return InputResponse.start_pan;
                    } else {
                        touch.* = TouchState.drag;
                        return InputResponse{ .start_drag = .{ .x = pressed[0].x, .y = pressed[0].y } };
                    }
                },
                else => {},
            }
        },
        TouchState.drag => {
            switch (touch_points) {
                0 => {
                    touch.* = TouchState{ .none = DOUBLE_THRESHOLD };
                    return InputResponse.stop_drag;
                },
                1 => {
                    return InputResponse{ .drag = .{
                        .x = rl.getTouchPosition(0).x,
                        .y = rl.getTouchPosition(0).y,
                        .r = 0.0,
                    } };
                },
                2 => {
                    const init_delta = rl.getTouchPosition(1).subtract(rl.getTouchPosition(0));
                    touch.* = TouchState{ .drag_rotate = .{init_delta} };
                    return InputResponse{ .drag = .{
                        .x = rl.getTouchPosition(0).x,
                        .y = rl.getTouchPosition(0).y,
                        .r = 0.0,
                    } };
                },
                else => {},
            }
        },
        TouchState.drag_rotate => |*drag_rotate| {
            switch (touch_points) {
                0 => {
                    touch.* = TouchState{ .none = DOUBLE_THRESHOLD };
                    return InputResponse.stop_drag;
                },
                1 => {
                    touch.* = TouchState.drag;
                    return InputResponse{ .drag = .{
                        .x = rl.getTouchPosition(0).x,
                        .y = rl.getTouchPosition(0).y,
                        .r = 0.0,
                    } };
                },
                2 => {
                    const new_delta = rl.getTouchPosition(1).subtract(rl.getTouchPosition(0));
                    const rotation = math.touch_rotate(
                        drag_rotate[0],
                        new_delta,
                        360.0,
                        2.0,
                    );
                    drag_rotate[0] = new_delta;
                    return InputResponse{ .drag = .{
                        .x = rl.getTouchPosition(0).x,
                        .y = rl.getTouchPosition(0).y,
                        .r = rotation,
                    } };
                },
                else => {},
            }
        },
        TouchState.panning => |*panning| {
            switch (touch_points) {
                0 => {
                    touch.* = TouchState{ .none = DOUBLE_THRESHOLD };
                    // state.camera_snap = false;
                    // if (state.camera_zoom >= 16.0) {
                    //     state.camera_zoom = 16.0;
                    // }
                    // if (state.camera_zoom < 0.5) {
                    //     state.camera_zoom = 0.5;
                    // }
                    // if (state.camera_position.x > FIELD_SIZE) {
                    //     state.camera_position.x = FIELD_SIZE;
                    // }
                    // if (state.camera_position.y > FIELD_SIZE) {
                    //     state.camera_position.y = FIELD_SIZE;
                    // }
                    // if (state.camera_position.x < -FIELD_SIZE) {
                    //     state.camera_position.x = -FIELD_SIZE;
                    // }
                    // if (state.camera_position.y < -FIELD_SIZE) {
                    //     state.camera_position.y = -FIELD_SIZE;
                    // }
                    // // NOTE: Snap angles to 45 degress for now.
                    // state.camera_rotation = math.snap_angle(state.camera_rotation, std.math.tau);
                    return InputResponse.stop_pan;
                },
                2 => {
                    const pinch = math.calc_pinch(
                        panning[0],
                        panning[1],
                        rl.getTouchPosition(0),
                        rl.getTouchPosition(1),
                        panning[2],
                        panning[3],
                        panning[4],
                        camera.offset,
                    );
                    return InputResponse{ .pan = .{
                        .x = pinch.t.x,
                        .y = pinch.t.y,
                        .z = pinch.z,
                        .r = pinch.r,
                    } };
                },
                else => {},
            }
        },
        TouchState.hold => {
            switch (touch_points) {
                0 => touch.* = TouchState{ .none = DOUBLE_THRESHOLD },
                else => {},
            }
        },
    }
    return InputResponse.none;
}
