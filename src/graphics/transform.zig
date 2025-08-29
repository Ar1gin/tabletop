const std = @import("std");
const math = @import("../math.zig");
const Transform = @This();

pub const TMatrix = @Vector(16, f32);

pub const Position = @Vector(3, f32);
pub const Rotation = @Vector(4, f32);
pub const Scale = f32;

position: Position = @splat(0.0),
rotation: Rotation = .{ 1.0, 0.0, 0.0, 0.0 },
scale: Scale = 1.0,

pub fn matrix(transform: Transform) TMatrix {
    @setFloatMode(.optimized);

    const r = rotationMatrix(transform.rotation) * @as(@Vector(9, f32), @splat(transform.scale));
    return .{
        r[0], r[1], r[2], transform.position[0],
        r[3], r[4], r[5], transform.position[1],
        r[6], r[7], r[8], transform.position[2],
        0.0,  0.0,  0.0,  1.0,
    };
}

pub fn inverseMatrix(transform: Transform) TMatrix {
    @setFloatMode(.optimized);

    const r = rotationMatrix(flipRotation(transform.rotation)) * @as(@Vector(9, f32), @splat(1.0 / transform.scale));
    const tx, const ty, const tz = transform.position;
    return .{
        r[0], r[1], r[2], -(r[0] * tx + r[1] * ty + r[2] * tz),
        r[3], r[4], r[5], -(r[3] * tx + r[4] * ty + r[5] * tz),
        r[6], r[7], r[8], -(r[6] * tx + r[7] * ty + r[8] * tz),
        0.0,  0.0,  0.0,  1.0,
    };
}

pub fn translate(transform: *Transform, translation: Position) void {
    @setFloatMode(.optimized);

    transform.position += translation;
}

pub fn translateLocal(transform: *Transform, translation: Position) void {
    @setFloatMode(.optimized);

    transform.position += rotateVector(translation, transform.rotation);
}

pub fn rotateVector(vector: Position, rotation: Rotation) Position {
    @setFloatMode(.optimized);

    const a = rotation[0];
    const b = rotation[1];
    const c = rotation[2];
    const d = rotation[3];

    const s = 2.0 / (a * a + b * b + c * c + d * d);
    const bs = b * s;
    const cs = c * s;
    const ds = d * s;

    const ab = a * bs;
    const ac = a * cs;
    const ad = a * ds;
    const bb = b * bs;
    const bc = b * cs;
    const bd = b * ds;
    const cc = c * cs;
    const cd = c * ds;
    const dd = d * ds;

    return .{
        vector[0] * (1 - cc - dd) + vector[1] * (bc - ad) + vector[2] * (bd + ac),
        vector[0] * (bc + ad) + vector[1] * (1 - bb - dd) + vector[2] * (cd - ab),
        vector[0] * (bd - ac) + vector[1] * (cd + ab) + vector[2] * (1 - bb - cc),
    };
}

pub fn rotate(transform: *Transform, rotation: Rotation) void {
    @setFloatMode(.optimized);

    // Also rotate `Position` around the origin?
    transform.rotation = normalizeRotation(combineRotations(transform.rotation, rotation));
}

pub fn rotateLocal(transform: *Transform, rotation: Rotation) void {
    @setFloatMode(.optimized);

    transform.rotation = normalizeRotation(combineRotations(rotation, transform.rotation));
}

pub fn rotateByAxis(transform: *Transform, axis: Position, angle: f32) void {
    transform.rotate(rotationByAxis(axis, angle));
}

pub fn rotateToward(transform: *Transform, target: Position, origin_norm: Position) void {
    @setFloatMode(.optimized);

    transform.rotation = rotationToward(origin_norm, target - transform.position, .{ .normalize_to = true });
}

const RotationTowardOptions = struct {
    normalize_from: bool = false,
    normalize_to: bool = false,
};
pub fn rotationToward(from: Position, to: Position, comptime options: RotationTowardOptions) Rotation {
    @setFloatMode(.optimized);

    const from_norm = if (options.normalize_from) extractNormal(from)[0] else from;
    const to_norm = if (options.normalize_to) extractNormal(to)[0] else to;

    const combined = combineRotations(.{
        0.0, to_norm[0], to_norm[1], to_norm[2],
    }, .{
        0.0, from_norm[0], from_norm[1], from_norm[2],
    });
    return normalizeRotation(.{
        1 - combined[0],
        combined[1],
        combined[2],
        combined[3],
    });
}

pub fn normalizeRotation(r: Rotation) Rotation {
    @setFloatMode(.optimized);

    const length = @sqrt(r[0] * r[0] + r[1] * r[1] + r[2] * r[2] + r[3] * r[3]);
    if (length <= 1e-15) {
        return .{ 1.0, 0.0, 0.0, 0.0 };
    } else {
        const length_inverse = 1.0 / length;
        return r * @as(Rotation, @splat(length_inverse));
    }
}

/// a: Child `Rotation`
/// b: Parent `Rotation`
pub fn combineRotations(a: Rotation, b: Rotation) Rotation {
    @setFloatMode(.optimized);

    return .{
        a[0] * b[0] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
        a[1] * b[0] + a[0] * b[1] + a[3] * b[2] - a[2] * b[3],
        a[2] * b[0] + a[0] * b[2] + a[1] * b[3] - a[3] * b[1],
        a[3] * b[0] + a[0] * b[3] + a[2] * b[1] - a[1] * b[2],
    };
}

pub fn rotationByAxis(axis: Position, angle: f32) Rotation {
    @setFloatMode(.optimized);

    const cos = std.math.cos(angle * 0.5);
    const sin = std.math.sin(angle * 0.5);

    return .{ cos, sin * axis[0], sin * axis[1], sin * axis[2] };
}

pub fn flipRotation(rotation: Rotation) Rotation {
    return .{
        rotation[0],
        -rotation[1],
        -rotation[2],
        -rotation[3],
    };
}

pub fn extractNormal(vector: Position) struct { Position, f32 } {
    @setFloatMode(.optimized);

    const length = @sqrt(vector[0] * vector[0] + vector[1] * vector[1] + vector[2] * vector[2]);
    if (length < 1e-15) {
        return .{ @Vector(3, f32){ 0, 0, -1 }, 1 };
    }
    return .{ vector / @as(Position, @splat(length)), length };
}

fn rotationMatrix(quaternion: Rotation) @Vector(9, f32) {
    @setFloatMode(.optimized);

    const a = quaternion[0];
    const b = quaternion[1];
    const c = quaternion[2];
    const d = quaternion[3];

    const s = 2.0 / (a * a + b * b + c * c + d * d);
    const bs = b * s;
    const cs = c * s;
    const ds = d * s;

    const ab = a * bs;
    const ac = a * cs;
    const ad = a * ds;
    const bb = b * bs;
    const bc = b * cs;
    const bd = b * ds;
    const cc = c * cs;
    const cd = c * ds;
    const dd = d * ds;

    return .{
        1 - cc - dd, bc - ad,     bd + ac,
        bc + ad,     1 - bb - dd, cd - ab,
        bd - ac,     cd + ab,     1 - bb - cc,
    };
}

pub fn multiplyMatrix(a: TMatrix, b: TMatrix) TMatrix {
    @setFloatMode(.optimized);

    var output: TMatrix = [1]f32{0.0} ** 16;
    for (0..4) |row| {
        for (0..4) |col| {
            for (0..4) |i| {
                output[row * 4 + col] += a[row * 4 + i] * b[i * 4 + col];
            }
        }
    }
    return output;
}

/// a: Child `Transform`
/// b: Parent `Transform`
pub fn combineTransforms(a: Transform, b: Transform) Transform {
    @setFloatMode(.optimized);

    return Transform{
        .position = rotateVector(a.position, b.rotation) * @as(Position, @splat(b.scale)) + b.position,
        .rotation = combineRotations(a.rotation, b.rotation),
        .scale = a.scale * b.scale,
    };
}

pub fn lerpTransformTimeLn(a: Transform, b: Transform, t: f32, lnf: f32) Transform {
    return lerpTransform(b, a, @exp(lnf * t));
}

pub fn lerpTransform(a: Transform, b: Transform, f: f32) Transform {
    @setFloatMode(.optimized);

    return Transform{
        .position = math.lerp(a.position, b.position, f),
        .rotation = math.slerp(a.rotation, b.rotation, f),
        .scale = math.lerp(a.scale, b.scale, f),
    };
}

pub const ZERO = Transform{};
