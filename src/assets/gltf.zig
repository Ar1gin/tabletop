const std = @import("std");
const sdl = @import("sdl");
const err = @import("../error.zig");
const Assets = @import("../assets.zig");
const Graphics = @import("../graphics.zig");

nodes: []Node,
meshes: []Mesh,

const Node = struct {
    mesh: u32,
};

const Mesh = struct {
    primitives: []Primitive,
};

const Primitive = struct {
    vertex_buffer: *sdl.GPUBuffer,
    index_buffer: ?*sdl.GPUBuffer = null,

    vertices: u32,
    indices: u32 = 0,
    texture: Assets.Texture,
};

const GltfJson = struct {
    scene: u32,
    scenes: []GltfSceneJson,
    nodes: []GltfNodeJson,
    materials: []GltfMaterialJson,
    meshes: []GltfMeshJson,
    textures: []GltfTextureJson,
    images: []GltfImageJson,
    accessors: []GltfAccessorJson,
    bufferViews: []GltfBufferViewJson,
    samplers: []GltfSamplerJson,
    buffers: []GltfBufferJson,

    const GltfSceneJson = struct {
        nodes: []u32,
    };
    const GltfNodeJson = struct {
        mesh: u32,
    };
    const GltfMaterialJson = struct {
        pbrMetallicRoughness: GltfPbrMRJson,

        const GltfPbrMRJson = struct {
            baseColorTexture: GltfPbrMRBaseColorTexture,

            const GltfPbrMRBaseColorTexture = struct {
                index: u32,
            };
        };
    };
    const GltfMeshJson = struct {
        primitives: []GltfPrimitiveJson,

        const GltfPrimitiveJson = struct {
            attributes: GltfAttributesJson,
            indices: u32,
            material: u32,

            const GltfAttributesJson = struct {
                POSITION: u32,
                TEXCOORD_0: u32,
            };
        };
    };
    const GltfTextureJson = struct {
        sampler: ?u32,
        source: u32,
    };
    const GltfImageJson = struct {
        uri: []u8,
    };
    const GltfAccessorJson = struct {
        bufferView: u32,
        componentType: GltfComponentTypeJson,
        count: u32,
        type: GltfAccessorTypeJson,

        const GltfComponentTypeJson = enum(u32) {
            i8 = 5120,
            u8 = 5121,
            i16 = 5122,
            u16 = 5123,
            i32 = 5125,
            f32 = 5126,
        };
        const GltfAccessorTypeJson = enum {
            SCALAR,
            VEC2,
            VEC3,
            VEC4,
            MAT2,
            MAT3,
            MAT4,
        };

        pub fn slice(accessor: @This(), comptime T: type, views: []const GltfBufferViewJson, buffers: []Assets.File) !?[]align(1) T {
            if (accessor.bufferView >= views.len) return null;
            const view = &views[accessor.bufferView];

            if (view.buffer >= buffers.len) return null;
            const buffer = try buffers[view.buffer].getSync();

            const component_length = switch (T) {
                [3]f32 => 12,
                [2]f32 => 8,
                u16 => 2,
                else => @compileError("Accessor of " ++ @tagName(accessor.type) ++ " of " ++ @tagName(accessor.componentType) ++ " is not supported."),
            };

            const start = view.byteOffset;
            const length = component_length * accessor.count;
            const end = start + length;

            if (length != view.byteLength) return error.ParsingError;

            return @as([]align(1) T, @ptrCast(buffer.bytes[start..end]));
        }
    };
    const GltfBufferViewJson = struct {
        buffer: u32,
        byteLength: u32,
        byteOffset: u32 = 0,
    };
    const GltfSamplerJson = struct {
        magFilter: GltfFilterJson = .NEAREST,
        minFilter: GltfFilterJson = .LINEAR,
        wrapS: GltfWrapJson = .CLAMP_TO_EDGE,
        wrapT: GltfWrapJson = .CLAMP_TO_EDGE,

        const GltfFilterJson = enum(u32) {
            NEAREST = 9728,
            LINEAR = 9729,
            NEAREST_MIPMAP_NEAREST = 9984,
            LINEAR_MIPMAP_NEAREST = 9985,
            NEAREST_MIPMAP_LINEAR = 9986,
            LINEAR_MIPMAP_LINEAR = 9987,
        };
        const GltfWrapJson = enum(u32) {
            CLAMP_TO_EDGE = 33071,
            MIRRORED_REPEAT = 33648,
            REPEAT = 10497,
        };
    };
    const GltfBufferJson = struct {
        // byteLength: u32,
        uri: []u8,
    };
};

pub fn load(path: []const u8, alloc: std.mem.Allocator) Assets.LoadError!@This() {
    var json = Assets.load(.file, path);
    defer Assets.free(json);

    const parsed_gltf = try std.json.parseFromSlice(
        GltfJson,
        alloc,
        (try json.getSync()).bytes,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed_gltf.deinit();
    const gltf = &parsed_gltf.value;

    if (gltf.scene >= gltf.scenes.len) return error.ParsingError;
    const scene = &gltf.scenes[gltf.scene];

    var buffers_init: u32 = 0;
    const buffers = try alloc.alloc(Assets.File, gltf.buffers.len);
    defer alloc.free(buffers);

    defer for (buffers[0..buffers_init]) |buffer| {
        Assets.free(buffer);
    };

    for (0.., buffers) |i, *buffer| {
        const buffer_path = try std.fs.path.join(alloc, &.{ std.fs.path.dirname(path) orelse return error.ParsingError, gltf.buffers[i].uri });
        defer alloc.free(buffer_path);
        buffer.* = Assets.load(.file, buffer_path);
        buffers_init += 1;
    }

    const nodes = try alloc.alloc(Node, scene.nodes.len);
    errdefer alloc.free(nodes);

    var meshes_init: u32 = 0;
    const meshes = try alloc.alloc(Mesh, gltf.meshes.len);
    errdefer alloc.free(nodes);

    errdefer for (meshes[0..meshes_init]) |*mesh| {
        for (mesh.primitives) |*primitive| {
            sdl.ReleaseGPUBuffer(Graphics.device, primitive.vertex_buffer);
            if (primitive.index_buffer) |buf| sdl.ReleaseGPUBuffer(Graphics.device, buf);
            Assets.free(primitive.texture);
        }
    };

    for (0.., nodes) |i, *node| {
        const node_index = scene.nodes[i];
        if (node_index >= gltf.nodes.len) return error.ParsingError;
        const gltf_node = &gltf.nodes[node_index];
        if (gltf_node.mesh >= gltf.meshes.len) return error.ParsingError;
        node.mesh = gltf_node.mesh;
    }
    for (0.., meshes) |i, *mesh| {
        const gltf_mesh = &gltf.meshes[i];

        var primitivs_init: u32 = 0;
        const primitives = try alloc.alloc(Primitive, gltf_mesh.primitives.len);
        errdefer alloc.free(primitives);

        errdefer for (primitives[0..primitivs_init]) |*primitive| {
            sdl.ReleaseGPUBuffer(Graphics.device, primitive.vertex_buffer);
            if (primitive.index_buffer) |buf| sdl.ReleaseGPUBuffer(Graphics.device, buf);
            Assets.free(primitive.texture);
        };

        for (0.., primitives) |j, *primitive| {
            const gltf_primitive = gltf_mesh.primitives[j];

            if (gltf_primitive.attributes.POSITION >= gltf.accessors.len) return error.ParsingError;
            if (gltf_primitive.attributes.TEXCOORD_0 >= gltf.accessors.len) return error.ParsingError;
            if (gltf_primitive.material >= gltf.materials.len) return error.ParsingError;
            const material = &gltf.materials[gltf_primitive.material];
            const texture_index = material.pbrMetallicRoughness.baseColorTexture.index;
            if (texture_index >= gltf.textures.len) return error.ParsingError;
            const texture = &gltf.textures[texture_index];
            if (texture.source >= gltf.images.len) return error.ParsingError;
            const image = &gltf.images[texture.source];

            const position = try gltf.accessors[gltf_primitive.attributes.POSITION].slice([3]f32, gltf.bufferViews, buffers) orelse return error.ParsingError;
            const uv = try gltf.accessors[gltf_primitive.attributes.TEXCOORD_0].slice([2]f32, gltf.bufferViews, buffers) orelse return error.ParsingError;
            const index = try gltf.accessors[gltf_primitive.indices].slice(u16, gltf.bufferViews, buffers) orelse return error.ParsingError;

            primitive.vertex_buffer, primitive.index_buffer = try loadMesh(position, uv, index, alloc);
            errdefer sdl.ReleaseGPUBuffer(Graphics.device, primitive.vertex_buffer);
            errdefer sdl.ReleaseGPUBuffer(Graphics.device, primitive.index_buffer);

            primitive.vertices = @intCast(position.len);
            primitive.indices = @intCast(index.len);

            const texture_path = try std.fs.path.join(alloc, &.{ std.fs.path.dirname(path) orelse return error.ParsingError, image.uri });
            defer alloc.free(texture_path);
            primitive.texture = Assets.load(.texture, texture_path);

            primitivs_init += 1;
        }

        mesh.primitives = primitives;
        meshes_init += 1;
    }

    return .{
        .nodes = nodes,
        .meshes = meshes,
    };
}

pub fn unload(self: @This(), alloc: std.mem.Allocator) void {
    for (self.meshes) |mesh| {
        for (mesh.primitives) |*primitive| {
            sdl.ReleaseGPUBuffer(Graphics.device, primitive.vertex_buffer);
            sdl.ReleaseGPUBuffer(Graphics.device, primitive.index_buffer);
            Assets.free(primitive.texture);
        }
        alloc.free(mesh.primitives);
    }
    alloc.free(self.meshes);
    alloc.free(self.nodes);
}

pub fn loadMesh(position: []align(1) const [3]f32, uv: []align(1) const [2]f32, index: []align(1) const u16, alloc: std.mem.Allocator) !struct { *sdl.GPUBuffer, *sdl.GPUBuffer } {
    if (position.len != uv.len) return error.ParsingError;
    const vertices: u32 = @intCast(position.len);
    const indices: u32 = @intCast(index.len);

    const BYTES_PER_VERTEX = 20;
    const BYTES_PER_INDEX = 2;

    const vertex_buffer = sdl.CreateGPUBuffer(Graphics.device, &.{
        .size = vertices * BYTES_PER_VERTEX,
        .usage = sdl.GPU_BUFFERUSAGE_VERTEX,
    }) orelse return error.SdlError;
    errdefer sdl.ReleaseGPUBuffer(Graphics.device, vertex_buffer);

    const index_buffer = sdl.CreateGPUBuffer(Graphics.device, &.{
        .size = indices * 2,
        .usage = sdl.GPU_BUFFERUSAGE_INDEX,
    }) orelse return error.SdlError;
    errdefer sdl.ReleaseGPUBuffer(Graphics.device, index_buffer);

    const TRANSFER_CAPACITY = Graphics.TRANSFER_BUFFER_DEFAULT_CAPACITY;

    const transfer_buffer = sdl.CreateGPUTransferBuffer(Graphics.device, &.{
        .size = TRANSFER_CAPACITY,
        .usage = sdl.GPU_TRANSFERBUFFERUSAGE_UPLOAD,
    }) orelse return error.SdlError;
    defer sdl.ReleaseGPUTransferBuffer(Graphics.device, transfer_buffer);

    const buffer = try alloc.alloc(u8, TRANSFER_CAPACITY);
    defer alloc.free(buffer);

    var vertices_uploaded: u32 = 0;
    while (vertices_uploaded < vertices) {
        const vertices_to_upload = @min(vertices - vertices_uploaded, TRANSFER_CAPACITY / BYTES_PER_VERTEX);
        if (vertices_to_upload == 0) return error.FileTooBig;

        for (0..vertices_to_upload) |i| {
            const V = packed struct { x: f32, y: f32, z: f32, u: f32, v: f32 };
            std.mem.copyForwards(
                u8,
                buffer[BYTES_PER_VERTEX * i ..],
                &@as([BYTES_PER_VERTEX]u8, @bitCast(V{
                    .x = position[vertices_uploaded + i][0],
                    .y = position[vertices_uploaded + i][1],
                    .z = position[vertices_uploaded + i][2],
                    .u = uv[vertices_uploaded + i][0],
                    .v = uv[vertices_uploaded + i][1],
                })),
            );
        }

        const command_buffer = sdl.AcquireGPUCommandBuffer(Graphics.device) orelse return error.SdlError;
        {
            errdefer _ = sdl.CancelGPUCommandBuffer(command_buffer);
            const copy_pass = sdl.BeginGPUCopyPass(command_buffer) orelse return error.SdlError;
            defer sdl.EndGPUCopyPass(copy_pass);

            const map: [*]u8 = @ptrCast(sdl.MapGPUTransferBuffer(Graphics.device, transfer_buffer, false) orelse err.sdl());
            @memcpy(map, buffer[0 .. vertices_to_upload * BYTES_PER_VERTEX]);
            sdl.UnmapGPUTransferBuffer(Graphics.device, transfer_buffer);

            sdl.UploadToGPUBuffer(copy_pass, &.{
                .transfer_buffer = transfer_buffer,
            }, &.{
                .buffer = vertex_buffer,
                .offset = vertices_uploaded * BYTES_PER_VERTEX,
                .size = vertices_to_upload * BYTES_PER_VERTEX,
            }, false);
        }
        vertices_uploaded += vertices_to_upload;
        const fence = sdl.SubmitGPUCommandBufferAndAcquireFence(command_buffer) orelse return error.SdlError;
        defer sdl.ReleaseGPUFence(Graphics.device, fence);
        if (!sdl.WaitForGPUFences(Graphics.device, true, &fence, 1)) return error.SdlError;
    }

    var indices_uploaded: u32 = 0;
    while (indices_uploaded < indices) {
        const indices_to_upload = @min(indices - indices_uploaded, TRANSFER_CAPACITY / BYTES_PER_INDEX);
        if (indices_to_upload == 0) return error.FileTooBig;

        for (0..indices_to_upload) |i| {
            std.mem.copyForwards(
                u8,
                buffer[BYTES_PER_INDEX * i ..],
                &@as([BYTES_PER_INDEX]u8, @bitCast(index[i])),
            );
        }

        const command_buffer = sdl.AcquireGPUCommandBuffer(Graphics.device) orelse return error.SdlError;
        {
            errdefer _ = sdl.CancelGPUCommandBuffer(command_buffer);
            const copy_pass = sdl.BeginGPUCopyPass(command_buffer) orelse return error.SdlError;
            defer sdl.EndGPUCopyPass(copy_pass);

            const map: [*]u8 = @ptrCast(sdl.MapGPUTransferBuffer(Graphics.device, transfer_buffer, false) orelse err.sdl());
            @memcpy(map, buffer[0 .. indices_to_upload * BYTES_PER_INDEX]);
            sdl.UnmapGPUTransferBuffer(Graphics.device, transfer_buffer);

            sdl.UploadToGPUBuffer(copy_pass, &.{
                .transfer_buffer = transfer_buffer,
            }, &.{
                .buffer = index_buffer,
                .offset = indices_uploaded * BYTES_PER_INDEX,
                .size = indices_to_upload * BYTES_PER_INDEX,
            }, false);
        }
        indices_uploaded += indices_to_upload;
        const fence = sdl.SubmitGPUCommandBufferAndAcquireFence(command_buffer) orelse return error.SdlError;
        defer sdl.ReleaseGPUFence(Graphics.device, fence);
        if (!sdl.WaitForGPUFences(Graphics.device, true, &fence, 1)) return error.SdlError;
    }

    return .{ vertex_buffer, index_buffer };
}
