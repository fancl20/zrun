const std = @import("std");
const runtime_spec = @import("runtime_spec.zig");
const syscall = @import("syscall.zig");

pub fn execute(alloc: std.mem.Allocator, process: *const runtime_spec.Process) !void {
    var arena_allocator = std.heap.ArenaAllocator.init(alloc);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    try std.os.setuid(process.user.uid);
    try std.os.setgid(process.user.gid);
    try std.os.chdir(process.cwd);
    _ = syscall.umask(process.user.umask);
    _ = try syscall.setgroups(process.user.additionalGids);

    const argv_buf = try arena.allocSentinel(?[*:0]const u8, process.args.len, null);
    for (process.args, 0..) |arg, i| {
        argv_buf[i] = (try arena.dupeZ(u8, arg)).ptr;
    }

    const envp = try arena.alloc(?[*:0]const u8, process.env.len + 1);
    var envp_i: usize = 0;
    for (process.env) |env| {
        envp[envp_i] = try arena.dupeZ(u8, env);
        envp_i += 1;
    }
    envp[envp_i] = null;

    _ = try std.os.prctl(.SET_CHILD_SUBREAPER, .{});

    return std.os.execveZ(argv_buf.ptr[0].?, argv_buf.ptr, envp[0..envp_i :null].ptr);
}

fn getenv(key: []const u8) ?[*:0]const u8 {
    for (std.os.environ) |line| {
        const env = std.mem.span(line);
        if (env.len < key.len + 1) {
            continue;
        }
        if (std.mem.startsWith(u8, env, key) and env[key.len] == '=') {
            return line;
        }
    }
    return null;
}
