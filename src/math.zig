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
pub fn lerp_angle(from: f32, to: f32, comptime speed: f32, comptime tau: f32, delta: f32) f32 {
    var target = to;
    if (@abs(from - target) > @abs(from - (target - tau))) {
        target -= tau;
    }
    if (@abs(from - target) > @abs(from - (target + tau))) {
        target += tau;
    }
    return lerp(from, target, speed, delta);
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

pub fn snap_angle(angle: f32, comptime tau: f32) f32 {
    const SNAP_F2: f32 = comptime blk: {
        break :blk tau * 0.125;
    };
    const SNAP_F1: f32 = 1.0 / SNAP_F2;

    return SNAP_F2 * std.math.round(angle * SNAP_F1);
}

pub fn calc_pinch(
    s1: rl.Vector2,
    s2: rl.Vector2,
    p1: rl.Vector2,
    p2: rl.Vector2,
    z1: f32,
    r1: f32,
    t1: rl.Vector2,
    o: rl.Vector2,
) struct { z: f32, r: f32, t: rl.Vector2 } {
    const z1r1 = Complex.init(
        z1 * std.math.cos(r1),
        z1 * std.math.sin(r1),
    );
    const z2r2 = z1r1.mul(Complex.init(
        p1.x - p2.x,
        p1.y - p2.y,
    )).mul(Complex.init(
        s1.x - s2.x,
        s1.y - s2.y,
    ).reciprocal());

    const z2 = z2r2.magnitude();
    const r2 = std.math.atan2(z2r2.im, z2r2.re);

    const t2 = Complex.init(
        s1.x - o.x,
        s1.y - o.y,
    ).mul(z1r1.reciprocal()).add(Complex.init(
        p1.x - o.x,
        p1.y - o.y,
    ).mul(z2r2.reciprocal()).neg()).add(Complex.init(
        t1.x,
        t1.y,
    ));
    return .{ .z = z2, .r = r2, .t = rl.Vector2.init(t2.re, t2.im) };
}

pub fn touch_rotate(start: rl.Vector2, end: rl.Vector2, comptime tau: f32, comptime factor: f32) f32 {
    const mult = comptime blk: {
        break :blk tau / std.math.tau * factor;
    };
    const normalized = Complex.div(
        Complex.init(end.x, end.y),
        Complex.init(start.x, start.y),
    );
    return std.math.atan2(normalized.im, normalized.re) * mult;
}
