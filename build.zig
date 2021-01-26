const builtin = @import("builtin");
const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const t = b.addTest("src/test.zig");

    const main = b.addExecutable("zrun", "src/zrun.zig");
    main.setBuildMode(b.standardReleaseOptions());
    main.setOutputDir("zig-cache");

    b.step("test", "Run all tests").dependOn(&t.step);
    b.default_step.dependOn(&main.step);
}
