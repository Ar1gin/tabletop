const std = @import("std");
const Build = std.Build;

/// Paths specified here are compiled to SPIR-V instead of being copied over
const SHADERS: []const []const u8 = &.{
    "data/shaders/basic.vert",
    "data/shaders/basic.frag",
};
const SDL_LIBS: []const []const u8 = &.{
    "SDL3",
    "SDL3_image",
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl_module, const sdl_step = stepSdlModule(b, target, optimize);

    const client_exe = stepBuildClient(b, target, optimize, sdl_module, sdl_step);
    const client_install = b.addInstallArtifact(client_exe, .{});

    const server_exe = stepBuildServer(b, target, optimize);
    const server_install = b.addInstallArtifact(server_exe, .{});

    const offline_exe = stepBuildOffline(b, target, optimize, sdl_module, sdl_step);
    const offline_install = b.addInstallArtifact(offline_exe, .{});

    const copy_data = stepCopyData(b, target, optimize);

    b.getInstallStep().dependOn(&client_install.step);
    b.getInstallStep().dependOn(&server_install.step);
    b.getInstallStep().dependOn(&offline_install.step);
    b.getInstallStep().dependOn(copy_data);

    const run = b.addRunArtifact(offline_exe);
    run.step.dependOn(&offline_install.step);
    run.step.dependOn(copy_data);

    // Why is this not the default behavior?
    run.setCwd(b.path(std.fs.path.relative(b.allocator, b.build_root.path.?, b.exe_dir) catch unreachable));

    if (b.args) |args| {
        run.addArgs(args);
    }

    const run_step = b.step("run", "Build and Run tabletop in offline mode");
    run_step.dependOn(&run.step);

    const check_step = b.step("check", "Check for build errors (offline build only)");
    check_step.dependOn(&offline_exe.step);
}

fn stepBuildClient(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sdl_module: *Build.Module,
    sdl_step: *Build.Step,
) *Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "tabletop_client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/client.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addImport("sdl", sdl_module);
    exe.step.dependOn(sdl_step);

    return exe;
}

fn stepBuildServer(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "tabletop_server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/server.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    return exe;
}

fn stepBuildOffline(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sdl_module: *Build.Module,
    sdl_step: *Build.Step,
) *Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "tabletop",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/offline.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addImport("sdl", sdl_module);
    exe.step.dependOn(sdl_step);

    return exe;
}

fn stepBuildSdlTranslator(
    b: *Build,
    target: Build.ResolvedTarget,
) *Build.Step.Compile {
    const sdl_translator = b.addExecutable(.{
        .name = "sdl_header_translator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("utils/sdl_translator.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    for (SDL_LIBS) |lib| {
        sdl_translator.linkSystemLibrary(lib);
    }
    return sdl_translator;
}

fn stepTranslateSdl(
    b: *Build,
    target: Build.ResolvedTarget,
) struct { *Build.Step, Build.LazyPath } {
    const sdl_translator = stepBuildSdlTranslator(b, target);
    const translate = b.addRunArtifact(sdl_translator);
    const sdl_rename = translate.addOutputFileArg("sdl_rename.h");
    return .{
        &translate.step,
        sdl_rename,
    };
}

fn stepSdlModule(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) struct { *Build.Module, *Build.Step } {
    const translate_sdl_step, const sdl_rename = stepTranslateSdl(b, target);

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("lib/sdl.h"),
        .link_libc = true,
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(sdl_rename.dirname());
    const translate_module = translate_c.createModule();
    for (SDL_LIBS) |lib| {
        translate_module.linkSystemLibrary(lib, .{ .needed = true });
    }

    translate_c.step.dependOn(translate_sdl_step);

    return .{
        translate_module,
        &translate_c.step,
    };
}

fn stepCopyData(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Build.Step {
    _ = &target;
    _ = &optimize;

    const copy_data_cmd = b.addInstallDirectory(.{
        .source_dir = b.path("data"),
        .install_dir = .bin,
        .install_subdir = "data",
        .exclude_extensions = &.{ "vert", "frag" },
    });
    const build_shaders = stepBuildShaders(b, target, optimize);

    copy_data_cmd.step.dependOn(build_shaders);

    return &copy_data_cmd.step;
}

fn stepBuildShaders(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Build.Step {
    _ = &target;

    const step = b.step("shaders", "Build all shaders with `glslc`");
    for (SHADERS) |shader_path| {
        const glslc = b.addSystemCommand(&.{"glslc"});
        if (optimize != .Debug) {
            glslc.addArg("-O");
        }

        const ext = std.fs.path.extension(shader_path);
        if (std.mem.eql(u8, ext, "vert")) {
            glslc.addArg("-fshader-stage=vert");
        }
        if (std.mem.eql(u8, ext, "frag")) {
            glslc.addArg("-fshader-stage=frag");
        }

        glslc.addFileArg(b.path(shader_path));
        glslc.addArg("-o");
        const shader_artifact = glslc.addOutputFileArg(std.fs.path.basename(shader_path));
        step.dependOn(&b.addInstallFileWithDir(shader_artifact, .bin, shader_path).step);
    }
    return step;
}
