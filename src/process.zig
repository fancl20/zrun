const std = @import("std");
const runtime_spec = @import("runtime_spec.zig");

pub fn execute(alloc: *std.mem.Allocator, spec: *const runtime_spec.Spec) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    try std.os.setuid(spec.process.user.uid);
    try std.os.setgid(spec.process.user.gid);
    try std.os.chdir(spec.process.cwd);

    var envs = std.BufMap.init(&arena.allocator);
    for (spec.process.env) |env| {
        const pos = std.mem.indexOf(u8, env, "=").?;
        try envs.set(env[0..pos], env[pos + 1 ..]);
    }
    return std.process.execve(&arena.allocator, spec.process.args, &envs);
}
