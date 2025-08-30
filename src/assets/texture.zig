const std = @import("std");
const sdl = @import("sdl");
const err = @import("../error.zig");
const c = @import("../c.zig");
const Assets = @import("../assets.zig");
const Graphics = @import("../graphics.zig");

texture: *sdl.GPUTexture,
sampler: *sdl.GPUSampler,

pub fn load(path: []const u8, alloc: std.mem.Allocator) Assets.LoadError!@This() {
    _ = alloc;
    var file = Assets.load(.file, path);
    defer Assets.free(file);
    const data = (try file.getSync()).bytes;

    var x: i32 = undefined;
    var y: i32 = undefined;
    var z: i32 = undefined;
    const image = c.stbi_load_from_memory(@ptrCast(data), @intCast(data.len), &x, &y, &z, 4);
    if (image == null) err.stbi();
    const image_slice = image[0..@intCast(x * y * z)];
    const texture, const sampler = Graphics.loadTexture(@intCast(x), @intCast(y), image_slice);
    c.stbi_image_free(image);
    return .{
        .texture = texture,
        .sampler = sampler,
    };
}

pub fn unload(self: @This(), alloc: std.mem.Allocator) void {
    _ = alloc;
    Graphics.unloadTexture(self.texture, self.sampler);
}
