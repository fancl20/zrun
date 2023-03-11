const builtin = @import("builtin");
const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const zrun = b.addExecutable(.{
        .name = "zrun",
        .root_source_file = .{ .path = "src/zrun.zig" },
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });

    zrun.setOutputDir("zig-cache");
    b.default_step.dependOn(&zrun.step);

    const zrun_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/zrun.zig" },
    });
    b.step("test", "Run all tests").dependOn(&zrun_tests.step);
}
