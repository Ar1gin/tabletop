const std = @import("std");
const Transform = @This();

// TODO: Scale

pub const TMatrix = @Vector(16, f32);

pub const Position = @Vector(3, f32);
pub const Rotation = @Vector(4, f32);
pub const Scale = @Vector(3, f32);

position: Position = @splat(0.0),
rotation: Rotation = .{ 1.0, 0.0, 0.0, 0.0 },
scale: Scale = @splat(1.0),

pub fn matrix(transform: Transform) TMatrix {
    const r = rotationMatrix(transform.rotation);
    return .{
        r[0], r[1], r[2], transform.position[0],
        r[3], r[4], r[5], transform.position[1],
        r[6], r[7], r[8], transform.position[2],
        0.0,  0.0,  0.0,  1.0,
    };
}

pub fn inverse(transform: Transform) TMatrix {
    // TODO: Could we just translate, rotate and scale back instead of relying on matrix math?
    return invertMatrix(transform.matrix());
}

pub fn rotate(transform: *Transform, rotation: Rotation) void {
    transform.rotation = normalizeRotation(combineRotations(transform.rotation, rotation));
}

pub fn normalizeRotation(r: Rotation) Rotation {
    @setFloatMode(.optimized);

    const length = @sqrt(r[0] * r[0] + r[1] * r[1] + r[2] * r[2] + r[3] * r[3]);
    return r / @as(Rotation, @splat(length));
}

pub fn combineRotations(a: Rotation, b: Rotation) Rotation {
    @setFloatMode(.optimized);

    return .{
        a[0] * b[0] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
        a[1] * b[0] + a[0] * b[1] + a[3] * b[2] - a[2] * b[3],
        a[2] * b[0] + a[0] * b[2] + a[1] * b[3] - a[3] * b[1],
        a[3] * b[0] + a[0] * b[3] + a[2] * b[1] - a[1] * b[2],
    };
}

pub fn rotationByAxis(axis: Position, rotation: f32) Rotation {
    @setFloatMode(.optimized);

    const cos = std.math.cos(rotation * 0.5);
    const sin = std.math.sin(rotation * 0.5);

    return .{ cos, sin * axis[0], sin * axis[1], sin * axis[2] };
}

pub fn extractNormal(vector: Position) struct { Position, f32 } {
    @setFloatMode(.optimized);

    const length = @sqrt(vector[0] * vector[0] + vector[1] * vector[1] + vector[2] * vector[2]);
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

fn invertMatrix(a: TMatrix) TMatrix {
    @setFloatMode(.optimized);

    const MOD: f32 = 1.0 / 16.0;
    const ID = TMatrix{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };
    var p = ID - @as(TMatrix, @splat(MOD)) * a;
    var output = ID + p;
    inline for (0..8) |_| {
        p = multiplyMatrix(p, p);
        output = multiplyMatrix(output, ID + p);
    }
    return output * @as(TMatrix, @splat(MOD));
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
