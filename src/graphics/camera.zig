const std = @import("std");
const sdl = @import("sdl");
const Transform = @import("transform.zig");
const Camera = @This();

transform: Transform,
/// tangent of the half of the view angle (90 degress = 1 "lens")
lens: f32,
near: f32,
far: f32,
/// width = height * aspect
aspect: f32,

pub fn matrix(camera: Camera) @Vector(16, f32) {
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
    return Transform.multiplyMatrix(projection, camera.transform.inverseMatrix());
}
