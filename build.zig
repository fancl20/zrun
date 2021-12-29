const builtin = @import("builtin");
const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const zrun = b.addExecutable("zrun", "src/zrun.zig");
    zrun.setBuildMode(b.standardReleaseOptions());
    zrun.setOutputDir("zig-cache");
    b.default_step.dependOn(&zrun.step);

    const socket_activate = b.addExecutable(
        "systemd-socket-activate",
        "src/utils/systemd-socket-activate.zig",
    );
    socket_activate.setBuildMode(b.standardReleaseOptions());
    socket_activate.setOutputDir("zig-cache");
    b.default_step.dependOn(&socket_activate.step);

    const zrun_tests = b.addTest("src/zrun.zig");
    b.step("test", "Run all tests").dependOn(&zrun_tests.step);
}
