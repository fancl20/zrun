const std = @import("std");
const runtime_spec = @import("runtime_spec.zig");

pub const Container = struct {
    allocator: *std.mem.Allocator,
    spec: runtime_spec.Spec,
    pub fn init(allocator: *std.mem.Allocator, spec: []const u8) !Container {
        return Container{
            .allocator = allocator,
            .spec = try std.json.parse(
                runtime_spec.Spec,
                &std.json.TokenStream.init(spec),
                .{ .allocator = std.testing.allocator },
            ),
        };
    }
    pub fn deinit(container: *Container) void {
        std.json.parseFree(
            runtime_spec.Spec,
            container.spec,
            .{ .allocator = container.allocator },
        );
    }
};

test "init and deinit container" {
    var container = try Container.init(std.testing.allocator, @embedFile("runtime_spec.json"));
    defer container.deinit();
}
