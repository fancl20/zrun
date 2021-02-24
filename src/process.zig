const std = @import("std");
const runtime_spec = @import("runtime_spec.zig");

pub fn execute(alloc: *std.mem.Allocator, process: *const runtime_spec.Process) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    try std.os.setuid(process.user.uid);
    try std.os.setgid(process.user.gid);
    try std.os.chdir(process.cwd);

    var envs = std.BufMap.init(&arena.allocator);
    for (process.bypassEnv) |env| {
        if (std.os.getenv(env)) |val| {
            try envs.set(env, val);
        }
    }
    for (process.env) |env| {
        const pos = std.mem.indexOf(u8, env, "=").?;
        try envs.set(env[0..pos], env[pos + 1 ..]);
    }

    return std.process.execve(&arena.allocator, process.args, &envs);
}
