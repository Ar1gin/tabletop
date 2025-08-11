const std = @import("std");
const Build = std.Build;

/// Paths specified here are compiled to SPIR-V instead of being copied over
const SHADERS: []const []const u8 = &.{
    "data/shaders/basic.vert",
    "data/shaders/basic.frag",
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = stepBuildMain(b, target, optimize);
    b.installArtifact(exe);

    const copy_data = stepCopyData(b, target, optimize);
    b.getInstallStep().dependOn(copy_data);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());

    // Why is this not the default behavoir?
    run.setCwd(b.path(std.fs.path.relative(b.allocator, b.build_root.path.?, b.exe_dir) catch unreachable));

    if (b.args) |args| {
        run.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run.step);

    const check_step = b.step("check", "Check for build errors");
    check_step.dependOn(&exe.step);
}

fn stepBuildMain(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "spacefarer",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const sdl_module, const sdl_step = stepSdlModule(b, target, optimize);
    exe.root_module.addImport("sdl", sdl_module);
    exe.step.dependOn(sdl_step);

    exe.addIncludePath(b.path("lib/clibs"));

    return exe;
}

fn stepBuildSdlTranslator(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Build.Step.Compile {
    const sdl_translator = b.addExecutable(.{
        .name = "sdl_header_translator",
        .root_source_file = b.path("utils/sdl_translator.zig"),
        .target = target,
        .optimize = optimize,
    });
    sdl_translator.linkSystemLibrary("SDL3");
    return sdl_translator;
}

fn stepTranslateSdl(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) struct { *Build.Step, Build.LazyPath } {
    const sdl_translator = stepBuildSdlTranslator(b, target, optimize);
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
    const sdl_module = b.addModule("sdl", .{
        .root_source_file = b.path("lib/sdl.zig"),
        .link_libc = true,
        .target = target,
        .optimize = optimize,
    });
    sdl_module.linkSystemLibrary("SDL3", .{});

    const translate_step, const sdl_rename = stepTranslateSdl(b, target, optimize);
    sdl_module.addIncludePath(sdl_rename.dirname());

    return .{
        sdl_module,
        translate_step,
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
