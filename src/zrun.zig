const std = @import("std");
const argparse = @import("argparse.zig");
const process = @import("process.zig");
const rootfs = @import("rootfs.zig");
const runtime_spec = @import("runtime_spec.zig");
const utils = @import("utils.zig");

const ZRunArgs = struct {
    bundle: []const u8 = ".",
    config: []const u8 = "runtime_spec.json",
    detach: bool = false,
    pid_file: ?[]const u8 = null,
};

pub fn main() !void {
    var alloc = std.heap.page_allocator;

    const zrun_args = try argparse.parse(ZRunArgs, .{ .allocator = alloc });
    defer argparse.parseFree(ZRunArgs, zrun_args, .{ .allocator = alloc });
    try std.os.chdir(zrun_args.bundle);

    // 0. Load configure
    var loader = try utils.JsonLoader(runtime_spec.Spec).initFromFile(alloc, zrun_args.config);
    defer loader.deinit();
    const runtime_config = loader.value;

    // 1. Unshare CLONE_NEWPID
    // - fork
    try utils.unshare(std.os.linux.CLONE_NEWPID);
    try utils.fork(zrun_args.detach);

    // 2. Unshare CLONE_NEWIPC
    try utils.unshare(std.os.linux.CLONE_NEWIPC);

    // 3. Unshare CLONE_NEWUTS
    // - Change hostname
    try utils.unshare(std.os.linux.CLONE_NEWUTS);
    if (runtime_config.hostname) |hostname| {
        try utils.sethostname(hostname);
    }

    // 4. Unshare CLONE_NEWNET
    // - Back to old network namespace
    // - Set up network
    // - Enter new network namespace
    try utils.unshare(std.os.linux.CLONE_NEWNET);

    // 5. Unshare CLONE_NEWNS
    // - Prepare rootfs (Mount private, generate files ...)
    // - Mount dirs to rootfs
    // - Create devices
    // - Chroot
    try utils.unshare(std.os.linux.CLONE_NEWNS);
    try rootfs.setup(alloc, &runtime_config);

    // 6. Finalize
    // - sysctl
    // - change user
    // - exec
    try process.execute(alloc, &runtime_config);
}
