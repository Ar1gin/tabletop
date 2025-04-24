const std = @import("std");

/// Paths specified here are compiled to SPIR-V instead of being copied over
const SHADERS: []const []const u8 = &.{
    "data/shaders/basic.vert",
    "data/shaders/basic.frag",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "spacefarer",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    exe.linkLibC();
    exe.linkSystemLibrary("SDL3");

    const copy_data_cmd = b.addInstallDirectory(.{
        .source_dir = b.path("data"),
        .install_dir = .bin,
        .install_subdir = "data",
        .exclude_extensions = &.{ "vert", "frag" },
    });
    b.getInstallStep().dependOn(&copy_data_cmd.step);

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
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(shader_artifact, .bin, shader_path).step);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.setCwd(b.path(std.fs.path.relative(b.allocator, b.build_root.path.?, b.exe_dir) catch unreachable));
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
