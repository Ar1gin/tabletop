const std = @import("std");

/// Smooth lerp
pub inline fn lerpTime(a: anytype, b: anytype, t: f32, comptime f: f32) @TypeOf(a, b) {
    @setFloatMode(.optimized);

    return lerpTimeLn(a, b, t, @log(f));
}

pub fn lerpTimeLn(a: anytype, b: anytype, t: f32, lnf: f32) @TypeOf(a, b) {
    @setFloatMode(.optimized);

    const a_factor = @exp(lnf * t);
    const b_factor = 1.0 - a_factor;

    switch (@typeInfo(@TypeOf(a, b))) {
        .float => return a_factor * a + b_factor * b,
        .vector => return @as(@TypeOf(a), @splat(a_factor)) * a + @as(@TypeOf(b), @splat(b_factor)) * b,
        else => @compileError("Can only interpolate between vector or float values"),
    }
}

/// Spherical lerp
pub inline fn slerpTime(a: anytype, b: anytype, t: f32, comptime f: f32) @TypeOf(a, b) {
    @setFloatMode(.optimized);

    return slerpTimeLn(a, b, t, @log(f));
}

pub fn slerpTimeLn(a: anytype, b: anytype, t: f32, lnf: f32) @TypeOf(a, b) {
    @setFloatMode(.optimized);

    const cos = @reduce(.Add, a * b);
    if (cos > 0.999) {
        return lerpTimeLn(a, b, t, lnf);
    }

    const angle = std.math.acos(cos);

    const a_angle_factor = @exp(lnf * t);
    const b_angle_factor = 1.0 - a_angle_factor;

    const rev_angle_sin = 1.0 / std.math.sin(angle);
    const a_sin = std.math.sin(a_angle_factor * angle);
    const b_sin = std.math.sin(b_angle_factor * angle);

    const a_factor = a_sin * rev_angle_sin;
    const b_factor = b_sin * rev_angle_sin;

    return @as(@TypeOf(a), @splat(a_factor)) * a + @as(@TypeOf(b), @splat(b_factor)) * b;
}

// Step interpolation
pub fn step(a: f32, b: f32, l: f32) f32 {
    @setFloatMode(.optimized);

    if (b > a) {
        return @min(a + l, b);
    } else {
        return @max(b, a - l);
    }
}

pub fn stepVector(a: anytype, b: anytype, l: f32) @TypeOf(a, b) {
    @setFloatMode(.optimized);

    return a + limitLength(b - a, l);
}

pub fn limitLength(vector: anytype, max_length: f32) @TypeOf(vector) {
    @setFloatMode(.optimized);

    const length_square = @reduce(.Add, vector * vector);
    if (length_square > max_length * max_length) {
        return vector * @as(@TypeOf(vector), @splat(max_length / @sqrt(length_square)));
    }
    return vector;
}

pub fn length(vector: anytype) f32 {
    @setFloatMode(.optimized);

    return @sqrt(dot(vector, vector));
}

pub fn dot(a: anytype, b: anytype) f32 {
    @setFloatMode(.optimized);

    return @reduce(.Add, a * b);
}
