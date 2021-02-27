const builtin = @import("builtin");
const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const zrun = b.addExecutable("zrun", "src/zrun.zig");
    zrun.setBuildMode(b.standardReleaseOptions());
    zrun.setOutputDir("zig-cache");

    const socket_activate = b.addExecutable(
        "systemd-socket-activate",
        "src/utils/systemd-socket-activate.zig",
    );
    socket_activate.setBuildMode(b.standardReleaseOptions());
    socket_activate.setOutputDir("zig-cache");

    const t = b.addTest("src/test.zig");

    b.step("test", "Run all tests").dependOn(&t.step);
    b.default_step.dependOn(&zrun.step);
    b.default_step.dependOn(&socket_activate.step);
}
