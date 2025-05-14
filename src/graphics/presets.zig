const sdl = @import("sdl");

pub const BLEND_NORMAL = sdl.GPUColorTargetBlendState{
    .enable_blend = true,
    .alpha_blend_op = sdl.GPU_BLENDOP_ADD,
    .color_blend_op = sdl.GPU_BLENDOP_ADD,
    .color_write_mask = sdl.GPU_COLORCOMPONENT_R | sdl.GPU_COLORCOMPONENT_G | sdl.GPU_COLORCOMPONENT_B | sdl.GPU_COLORCOMPONENT_A,
    .src_alpha_blendfactor = sdl.GPU_BLENDFACTOR_ONE,
    .src_color_blendfactor = sdl.GPU_BLENDFACTOR_SRC_ALPHA,
    .dst_alpha_blendfactor = sdl.GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
    .dst_color_blendfactor = sdl.GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
};

pub const DEPTH_ENABLED = sdl.GPUDepthStencilState{
    .compare_op = sdl.GPU_COMPAREOP_LESS,
    .enable_depth_test = true,
    .enable_depth_write = true,
};

pub const RASTERIZER_CULL = sdl.GPURasterizerState{
    .cull_mode = sdl.GPU_CULLMODE_BACK,
    .fill_mode = sdl.GPU_FILLMODE_FILL,
    .front_face = sdl.GPU_FRONTFACE_CLOCKWISE,
};
