const std = @import("std");

const SHADERS: []const struct { file: []const u8, stage: []const u8 } = &.{
    .{ .file = "basic", .stage = "vert" },
    .{ .file = "basic", .stage = "frag" },
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

    inline for (SHADERS) |shader| {
        const glslc = b.addSystemCommand(&.{"glslc"});
        glslc.addArg("-fshader-stage=" ++ shader.stage);
        glslc.addFileArg(b.path("assets/shaders/" ++ shader.file ++ "." ++ shader.stage));
        glslc.addArg("-o");
        const filename = shader.file ++ "_" ++ shader.stage ++ ".spv";
        const shader_artifact = glslc.addOutputFileArg(filename);
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(shader_artifact, .prefix, filename).step);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
