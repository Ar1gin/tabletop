const std = @import("std");
const sdl = @import("sdl");
const err = @import("error.zig");
const c = @import("c.zig");
const comp = @import("components.zig");
const Game = @import("game.zig");
const Graphics = @import("graphics.zig");
const Assets = @This();

const Storage = comp.Storage(Asset, .{});

var storage: Storage = undefined;

pub const AssetType = enum {
    texture,
};
pub const Texture = struct {
    handle: Storage.Key,
};

const Asset = struct {
    path: []const u8,
    data: union(AssetType) {
        texture: AssetTexture,
    },
};
pub const AssetTexture = struct {
    texture: *sdl.GPUTexture,
    sampler: *sdl.GPUSampler,
};

pub fn init() void {
    Assets.storage = Storage.init();
}
pub fn deinit() void {
    var iter = Assets.storage.iter();
    while (iter.next()) |asset| {
        Assets.freeAsset(asset);
    }
    Assets.storage.deinit();
}
pub fn load(comptime asset_type: AssetType, path: []const u8) typeFromAssetType(asset_type) {
    switch (asset_type) {
        .texture => {
            const data = loadFile(Game.alloc, path) catch |e| err.file(e, path);
            var x: i32 = undefined;
            var y: i32 = undefined;
            var z: i32 = undefined;
            const image = c.stbi_load_from_memory(@ptrCast(data), @intCast(data.len), &x, &y, &z, 4);
            Game.alloc.free(data);
            if (image == null) err.stbi();
            const image_slice = image[0..@intCast(x * y * z)];
            const texture, const sampler = Graphics.loadTexture(@intCast(x), @intCast(y), image_slice);
            c.stbi_image_free(image);
            return .{ .handle = Assets.storage.add(.{
                .path = path,
                .data = .{ .texture = .{
                    .texture = texture,
                    .sampler = sampler,
                } },
            }) };
        },
    }
}
pub fn free(asset: anytype) void {
    if (Assets.storage.free(asset.handle)) |stored| {
        freeAsset(stored);
    }
}
pub fn freeAsset(asset: *Asset) void {
    switch (asset.data) {
        .texture => {
            Graphics.unloadTexture(asset.data.texture.texture, asset.data.texture.sampler);
        },
    }
}
pub fn get(asset: anytype) ?assetTypeFromType(@TypeOf(asset)) {
    if (Assets.storage.get(asset.handle)) |stored| {
        switch (@TypeOf(asset)) {
            Texture => {
                return stored.data.texture;
            },
            else => @compileError("Cannot get asset of type " ++ @typeName(@TypeOf(asset))),
        }
    }
    unreachable;
}

fn loadFile(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(alloc, std.math.maxInt(i32));
}
fn typeFromAssetType(comptime asset_type: AssetType) type {
    return switch (asset_type) {
        .texture => Texture,
    };
}
fn assetTypeFromType(comptime T: type) type {
    return switch (T) {
        Texture => AssetTexture,
        else => unreachable,
    };
}
