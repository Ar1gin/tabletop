const std = @import("std");
const rl = @import("raylib");

const Complex = std.math.Complex(f32);

pub fn lerp(from: f32, to: f32, comptime speed: f32, delta: f32) f32 {
    // Gotta go fast
    const exp_factor = comptime blk: {
        break :blk @log(1.0 - speed);
    };
    const factor_from = @exp(exp_factor * delta);
    const factor_to = 1.0 - factor_from;
    return factor_from * from + factor_to * to;
}

pub fn complex_rotation(rotation: f32) Complex {
    return Complex.init(
        std.math.cos(rotation),
        std.math.sin(rotation),
    );
}

pub fn comp_to_vec(complex: Complex) rl.Vector2 {
    return rl.Vector2{
        .x = complex.re,
        .y = complex.im,
    };
}
