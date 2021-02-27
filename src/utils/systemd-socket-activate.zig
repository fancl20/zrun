const std = @import("std");

pub fn main() !void {
    return std.process.execve(&arena.allocator, process.args, &envs);
}
