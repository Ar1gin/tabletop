const std = @import("std");
const sdl = @import("sdl");
const err = @import("../error.zig");
const Assets = @import("../assets.zig");
const Graphics = @import("../graphics.zig");

texture: *sdl.GPUTexture,
sampler: *sdl.GPUSampler,

pub fn load(path: []const u8, alloc: std.mem.Allocator) Assets.LoadError!@This() {
    _ = alloc;
    var file = Assets.load(.file, path);
    defer Assets.free(file);
    const data = (file.getSync() catch return error.DependencyError).bytes;

    const image: *sdl.Surface = @ptrCast(sdl.IMG_Load_IO(sdl.IOFromConstMem(data.ptr, data.len), true) orelse return error.ParsingError);
    defer sdl.DestroySurface(image);
    const format = image.format;

    const width: u32 = @intCast(image.w);
    const height: u32 = @intCast(image.h);
    const channels: u32 = 4;

    const image_slice = @as([*]u8, @ptrCast(image.pixels))[0..@intCast(width * height * channels)];

    if (width > 8192 or height > 8192) return error.FileTooBig;

    const target_format = sdl.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
    const bytes_per_pixel = 4;
    const mip_level = if (std.math.isPowerOfTwo(width) and width == height) @as(u32, Graphics.MIP_LEVEL) else @as(u32, 1);

    const texture = sdl.CreateGPUTexture(Graphics.device, &.{
        .width = width,
        .height = height,
        .layer_count_or_depth = 1,
        .format = target_format,
        .usage = sdl.GPU_TEXTUREUSAGE_SAMPLER | sdl.GPU_TEXTUREUSAGE_COLOR_TARGET,
        .num_levels = mip_level,
    }) orelse err.sdl();
    errdefer Graphics.freeTexture(texture);

    const transfer_buffer_capacity = Graphics.TRANSFER_BUFFER_DEFAULT_CAPACITY;
    const transfer_buffer = sdl.CreateGPUTransferBuffer(Graphics.device, &.{
        .size = transfer_buffer_capacity,
        .usage = sdl.GPU_TRANSFERBUFFERUSAGE_UPLOAD,
    }) orelse return error.SdlError;
    defer sdl.ReleaseGPUTransferBuffer(Graphics.device, transfer_buffer);

    var rows_uploaded: u32 = 0;
    while (rows_uploaded < height) {
        const rows_to_upload = @min(height - rows_uploaded, transfer_buffer_capacity / width / bytes_per_pixel);
        if (rows_to_upload == 0) return error.FileTooBig;

        const command_buffer = sdl.AcquireGPUCommandBuffer(Graphics.device) orelse return error.SdlError;
        {
            errdefer _ = sdl.CancelGPUCommandBuffer(command_buffer);
            const copy_pass = sdl.BeginGPUCopyPass(command_buffer) orelse return error.SdlError;
            defer sdl.EndGPUCopyPass(copy_pass);

            const map: [*]u8 = @ptrCast(sdl.MapGPUTransferBuffer(Graphics.device, transfer_buffer, false) orelse err.sdl());
            var pixel: u32 = rows_uploaded * width * bytes_per_pixel;
            var mapped: u32 = 0;
            while (pixel < (rows_uploaded + rows_to_upload) * width * bytes_per_pixel) {
                defer pixel += bytes_per_pixel;
                defer mapped += bytes_per_pixel;
                switch (format) {
                    // Convert to RGBA8888
                    sdl.PIXELFORMAT_ABGR8888 => {
                        map[mapped + 0] = image_slice[pixel + 3];
                        map[mapped + 1] = image_slice[pixel + 2];
                        map[mapped + 2] = image_slice[pixel + 1];
                        map[mapped + 3] = image_slice[pixel + 0];
                    },
                    sdl.PIXELFORMAT_ARGB8888 => {
                        map[mapped + 0] = image_slice[pixel + 1];
                        map[mapped + 1] = image_slice[pixel + 2];
                        map[mapped + 2] = image_slice[pixel + 3];
                        map[mapped + 3] = image_slice[pixel + 0];
                    },
                    sdl.PIXELFORMAT_RGBA8888 => {
                        map[mapped + 0] = image_slice[pixel + 0];
                        map[mapped + 1] = image_slice[pixel + 1];
                        map[mapped + 2] = image_slice[pixel + 2];
                        map[mapped + 3] = image_slice[pixel + 3];
                    },
                    sdl.PIXELFORMAT_BGRA8888 => {
                        map[mapped + 0] = image_slice[pixel + 2];
                        map[mapped + 1] = image_slice[pixel + 1];
                        map[mapped + 2] = image_slice[pixel + 0];
                        map[mapped + 3] = image_slice[pixel + 3];
                    },
                    else => {
                        sdl.UnmapGPUTransferBuffer(Graphics.device, transfer_buffer);
                        return error.UnsupportedAsset;
                    },
                }
            }
            @memcpy(map, image_slice[(rows_uploaded * width * bytes_per_pixel)..((rows_uploaded + rows_to_upload) * width * bytes_per_pixel)]);
            sdl.UnmapGPUTransferBuffer(Graphics.device, transfer_buffer);

            sdl.UploadToGPUTexture(copy_pass, &sdl.GPUTextureTransferInfo{
                .offset = 0,
                .pixels_per_row = width,
                .rows_per_layer = rows_to_upload,
                .transfer_buffer = transfer_buffer,
            }, &sdl.GPUTextureRegion{
                .texture = texture,
                .mip_level = 0,
                .layer = 0,
                .x = 0,
                .y = rows_uploaded,
                .z = 0,
                .w = width,
                .h = rows_to_upload,
                .d = 1,
            }, false);
        }
        rows_uploaded += rows_to_upload;
        if (rows_uploaded == height and mip_level > 1) {
            sdl.GenerateMipmapsForGPUTexture(command_buffer, texture);
        }
        const fence = sdl.SubmitGPUCommandBufferAndAcquireFence(command_buffer) orelse return error.SdlError;
        defer sdl.ReleaseGPUFence(Graphics.device, fence);
        if (!sdl.WaitForGPUFences(Graphics.device, true, &fence, 1)) return error.SdlError;
    }

    const sampler = Graphics.createSampler(mip_level);

    return .{
        .texture = texture,
        .sampler = sampler,
    };
}

pub fn unload(self: @This(), alloc: std.mem.Allocator) void {
    _ = alloc;
    Graphics.freeTexture(self.texture);
    Graphics.freeSampler(self.sampler);
}
