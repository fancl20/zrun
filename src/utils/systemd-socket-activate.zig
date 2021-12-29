const std = @import("std");

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    var arena = arena_allocator.allocator();

    var envs = try arena.allocSentinel(?[*:0]const u8, std.os.environ.len + 1, null);
    envs[0] = try std.fmt.allocPrintZ(arena, "LISTEN_PID={}", .{std.os.linux.getpid()});
    for (std.os.environ) |env, i| {
        envs[i + 1] = env;
    }
    const argv = std.os.argv;
    return std.os.execveZ(argv[1], @ptrCast([*:null]const ?[*:0]const u8, argv[1..].ptr), envs.ptr);
}
