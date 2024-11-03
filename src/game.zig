const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const GameTexture = rl.Rectangle;
const FIELD_SIZE: f32 = 16.0;

pub const GameState = struct {
    alloc: std.mem.Allocator,
    camera: rl.Camera2D,
    camera_resolution: f32,
    camera_zoom: f32,
    camera_position: rl.Vector2,
    camera_rotation: f32,
    items: std.ArrayList(TableItem),
    hand: std.ArrayList(Card),
    touch_state: TouchState,

    const TouchState = union(enum) {
        none,
        single: rl.Vector2,
        double: struct {
            rl.Vector2,
            rl.Vector2,
            f32,
            f32,
            f32,
            rl.Vector2,
        },
    };

    const Self = @This();
    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .alloc = alloc,
            .camera = rl.Camera2D{
                .offset = rl.Vector2.zero(),
                .target = rl.Vector2.zero(),
                .zoom = 1.0,
                .rotation = 0.0,
            },
            .camera_resolution = 1.0,
            .camera_zoom = 1.0,
            .camera_position = rl.Vector2{ .x = 0.0, .y = 0.0 },
            .camera_rotation = 0.0,
            .items = std.ArrayList(TableItem).init(alloc),
            .hand = std.ArrayList(Card).init(alloc),
            .touch_state = TouchState.none,
        };
    }
    pub fn deinit(self: *Self) void {
        self.items.deinit();
        self.hand.deinit();
    }
    pub fn update(self: *Self, delta: f32) void {
        _ = delta;
        const touch_points = rl.getTouchPointCount();
        switch (touch_points) {
            else => {
                if (self.touch_state != TouchState.none) {
                    self.touch_state = TouchState.none;
                }
            },
            1 => {
                const position = rl.getTouchPosition(0);
                if (self.touch_state != TouchState.single) {
                    self.touch_state = TouchState{ .single = position };
                } else {
                    const world_delta = rl.getScreenToWorld2D(position, self.camera)
                        .subtract(rl.getScreenToWorld2D(self.touch_state.single, self.camera));
                    self.camera_position = self.camera_position.subtract(world_delta);
                    self.touch_state = TouchState{ .single = position };
                }
            },
            2 => {
                const position1 = rl.getTouchPosition(0);
                const position2 = rl.getTouchPosition(1);
                if (self.touch_state != TouchState.double) {
                    // That's IMPOSSIBLE, duh
                    if (position1.equals(position2) == 0) {
                        std.debug.print("Initializing pinch calculation\n", .{});
                        self.touch_state = TouchState{ .double = .{
                            position1,
                            position2,
                            self.camera_resolution,
                            self.camera_zoom,
                            self.camera_rotation,
                            self.camera_position,
                        } };
                    }
                } else {
                    const start1 = self.touch_state.double[0];
                    const start2 = self.touch_state.double[1];
                    const resolution = self.touch_state.double[2];
                    const zoom1 = self.touch_state.double[3] * resolution;
                    const rotation1 = self.touch_state.double[4];
                    const target1 = self.touch_state.double[5];

                    const Complex = std.math.Complex(f32);

                    const z1r1 = Complex.init(
                        zoom1 * std.math.cos(rotation1),
                        zoom1 * std.math.sin(rotation1),
                    );
                    const z2r2 = z1r1.mul(Complex.init(
                        position1.x - position2.x,
                        position1.y - position2.y,
                    )).mul(Complex.init(
                        start1.x - start2.x,
                        start1.y - start2.y,
                    ).reciprocal());

                    const zoom2 = z2r2.magnitude();
                    const rotation2 = std.math.atan2(z2r2.im, z2r2.re);
                    const target2 = Complex.init(
                        start1.x - self.camera.offset.x,
                        start1.y - self.camera.offset.y,
                    ).mul(z1r1.reciprocal()).add(Complex.init(
                        position1.x - self.camera.offset.x,
                        position1.y - self.camera.offset.y,
                    ).mul(z2r2.reciprocal()).neg()).add(Complex.init(
                        target1.x,
                        target1.y,
                    ));

                    self.camera_zoom = zoom2 / resolution;
                    self.camera_rotation = rotation2;
                    self.camera_position.x = target2.re;
                    self.camera_position.y = target2.im;
                }
            },
        }
    }
    pub fn draw(self: *Self) void {
        const vzoom = @as(f32, @floatFromInt(rl.getScreenHeight())) / 16.0;
        const hzoom = @as(f32, @floatFromInt(rl.getScreenWidth())) / 16.0;

        self.camera_resolution = @min(vzoom, hzoom);
        self.camera.zoom = self.camera_resolution * self.camera_zoom;
        self.camera.offset = rl.Vector2{
            .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
            .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
        };
        self.camera.target = self.camera_position;
        self.camera.rotation = self.camera_rotation * std.math.deg_per_rad;
        {
            rl.beginMode2D(self.camera);
            defer rl.endMode2D();

            rl.drawRectangle(-8, -8, 16, 16, rl.Color.dark_gray);
            rl.drawRectangle(7, 7, 1, 1, rl.Color.red);
        }
    }
};

const TableItem = struct {
    position: rl.Vector2,
    rotation: f32,
    storage: Storage,

    const Storage = union(enum) {
        card: Card,
        deck: std.ArrayList(Card),
        stack: std.ArrayList(Card),
    };
};
const Card = struct {
    size: rl.Vector2,
    face_up: bool,
    face_texture: rl.Rectangle,
    back_texture: rl.Rectangle,
};
