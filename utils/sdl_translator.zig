const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_image/SDL_image.h");
});

const PREFIX = "SDL_";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

    var arg_iter = try std.process.argsWithAllocator(alloc);

    _ = arg_iter.next();
    const output = arg_iter.next().?;

    const file = if (std.fs.path.isAbsolute(output))
        try std.fs.createFileAbsolute(output, .{})
    else
        try std.fs.cwd().createFile(output, .{});
    defer file.close();

    var writer_buffer: [4096]u8 = undefined;
    var writer = file.writer(&writer_buffer);

    var renamed_count: usize = 0;
    for (@typeInfo(sdl).@"struct".decls) |decl| {
        if (!std.mem.startsWith(u8, decl.name, PREFIX)) continue;

        const new_name: []const u8 = decl.name[PREFIX.len..];

        try writer.interface.print(
            \\#define {1s} {0s}
            \\
        , .{ decl.name, new_name });
        renamed_count += 1;
    }
    if (renamed_count == 0) {
        @panic("No SDL definitions renamed");
    }
}
