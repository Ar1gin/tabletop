const std = @import("std");
const sdl = @import("sdl");
const math = @import("../math.zig");
const Transform = @import("transform.zig");
const Camera = @This();

transform: Transform,
/// tangent of the half of the view angle (90 degress = 1 "lens")
lens: f32,
near: f32,
far: f32,
/// width = height * aspect
aspect: f32,

matrix: Transform.TMatrix,

pub fn computeMatrix(camera: *Camera) void {
    @setFloatMode(.optimized);

    const xx = 1.0 / (camera.lens * camera.aspect);
    const yy = 1.0 / camera.lens;
    const fnmod = 1.0 / (camera.far - camera.near);
    const zz = camera.far * fnmod;
    const wz = -camera.near * camera.far * fnmod;
    const projection = @Vector(16, f32){
        xx, 0,  0,   0,
        0,  yy, 0,   0,
        0,  0,  -zz, wz,
        0,  0,  -1,  0,
    };
    camera.matrix = Transform.multiplyMatrix(projection, camera.transform.inverseMatrix());
}

pub fn to_screen(camera: Camera, position: Transform.Position) @Vector(2, f32) {
    @setFloatMode(.optimized);

    var x: f32 = camera.matrix[3];
    var y: f32 = camera.matrix[7];
    var w: f32 = camera.matrix[15];

    for (0..3) |i| {
        x += camera.matrix[i] * position[i];
    }
    for (0..3) |i| {
        y += camera.matrix[i + 4] * position[i];
    }
    for (0..3) |i| {
        w += camera.matrix[i + 12] * position[i];
    }
    @setRuntimeSafety(false);
    const wmod = 1 / w;
    return .{ x * wmod, y * wmod };
}

pub fn mouse_in_quad(camera: Camera, mouse: @Vector(2, f32), quad_transform: Transform, width: f32, height: f32) bool {
    @setFloatMode(.optimized);

    const matrix = Transform.multiplyMatrix(camera.matrix, quad_transform.matrix());

    const hw = width * 0.5;
    const hh = height * 0.5;
    const pi: [4]@Vector(2, f32) = .{
        .{ -hw, -hh },
        .{ -hw,  hh },
        .{  hw,  hh },
        .{  hw, -hh },
    };
    var po: [4]@Vector(2, f32) = undefined;
    for (0..4) |i| {
        const x = matrix[0] * pi[i][0] + matrix[1] * pi[i][1] + matrix[3];
        const y = matrix[4] * pi[i][0] + matrix[5] * pi[i][1] + matrix[7];
        const w = matrix[12] * pi[i][0] + matrix[13] * pi[i][1] + matrix[15];
        @setRuntimeSafety(false);
        po[i] = .{ x / w, y / w };
    }
    inline for (0..4) |i| {
        const a = po[i];
        const b = po[(i + 1) % 4];
        const c = mouse;
        if ((c[0] - a[0]) * (b[1] - a[1]) - (c[1] - a[1]) * (b[0] - a[0]) < 0.0) {
            return false;
        }
    }

    return true;
}

pub fn raycast(camera: Camera, mouse: @Vector(2, f32), plane: @Vector(4, f32)) @Vector(3, f32) {
    const matrix = camera.transform.matrix();

    const local = @Vector(3, f32){
        mouse[0] * camera.lens * camera.aspect,
        mouse[1] * camera.lens,
        -1,
    };
    var global = @Vector(3, f32){
        matrix[3],
        matrix[7],
        matrix[11],
    };
    for (0..3) |i| {
        for (0..3) |j| {
            global[i] += local[j] * matrix[4 * i + j];
        }
    }

    return math.raycast(camera.transform.position, global, plane);
}
