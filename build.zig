const builtin = @import("builtin");
const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const zrun = b.addExecutable("zrun", "src/zrun.zig");
    zrun.setBuildMode(b.standardReleaseOptions());
    zrun.linkLibC();
    zrun.setTarget(.{ .abi = .musl });
    zrun.setOutputDir("zig-cache");

    const t = b.addTest("src/test.zig");

    b.step("test", "Run all tests").dependOn(&t.step);
    b.default_step.dependOn(&zrun.step);
}
