const std = @import("std");
const process = @import("process.zig");
const rootfs = @import("rootfs.zig");
const runtime_spec = @import("runtime_spec.zig");
const utils = @import("utils.zig");

pub fn main() !void {
    var alloc = std.heap.page_allocator;

    const runtime_config_path = utils.ptrZtoSlice(std.os.argv[1]);

    // 0. Load configure
    var loader = try utils.JsonLoader(runtime_spec.Spec).initFromFile(alloc, runtime_config_path);
    defer loader.deinit();
    const runtime_config = loader.value;

    // 1. Unshare CLONE_NEWPID
    // - fork
    try utils.unshare(std.os.linux.CLONE_NEWPID);
    const pid = try std.os.fork();
    if (pid != 0) {
        _ = std.os.waitpid(pid, 0);
        return;
    }

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
