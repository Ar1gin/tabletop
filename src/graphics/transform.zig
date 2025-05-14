const std = @import("std");
const Transform = @This();

// TODO: Rotation

position: @Vector(3, f32) = @splat(0.0),
rotation: @Vector(3, f32) = @splat(0.0),
scale: @Vector(3, f32) = @splat(1.0),

pub fn matrix(transform: Transform) @Vector(16, f32) {
    return .{
        1.0, 0.0, 0.0, transform.position[0],
        0.0, 1.0, 0.0, transform.position[1],
        0.0, 0.0, 1.0, transform.position[2],
        0.0, 0.0, 0.0, 1.0,
    };
}

pub fn inverse(transform: Transform) @Vector(16, f32) {
    // TODO: Could we just translate, rotate and scale back instead of relying on matrix math?
    return invertMatrix(transform.matrix());
}

fn invertMatrix(a: @Vector(16, f32)) @Vector(16, f32) {
    const MOD: f32 = 1.0 / 16.0;
    const ID = @Vector(16, f32){
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };
    var p = ID - @as(@Vector(16, f32), @splat(MOD)) * a;
    var output = ID + p;
    inline for (0..8) |_| {
        p = multiplyMatrix(p, p);
        output = multiplyMatrix(output, ID + p);
    }
    return output * @as(@Vector(16, f32), @splat(MOD));
}

pub fn multiplyMatrix(a: @Vector(16, f32), b: @Vector(16, f32)) @Vector(16, f32) {
    var output: @Vector(16, f32) = [1]f32{0.0} ** 16;

    @setFloatMode(.optimized);
    for (0..4) |row| {
        for (0..4) |col| {
            for (0..4) |i| {
                output[row * 4 + col] += a[row * 4 + i] * b[i * 4 + col];
            }
        }
    }
    return output;
}
