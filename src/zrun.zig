const std = @import("std");
const argparse = @import("argparse.zig");
const process = @import("process.zig");
const rootfs = @import("rootfs.zig");
const runtime_spec = @import("runtime_spec.zig");
const syscall = @import("syscall.zig");
const utils = @import("utils.zig");

const ZRunArgs = struct {
    bundle: []const u8 = ".",
    config: []const u8 = "runtime_spec.json",
    detach: bool = false,
    pid_file: ?[]const u8 = null,
};

fn zrun() !?utils.Process {
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
    try utils.setupNamespace(.pid, runtime_config.linux.namespaces);
    if (try utils.fork()) |child| {
        if (zrun_args.pid_file) |pid_file| {
            try child.createPidFile(pid_file);
        }
        // TODO: Return continuation instead
        return if (zrun_args.detach) null else child;
    }

    // 2. Unshare CLONE_NEWIPC
    try utils.setupNamespace(.ipc, runtime_config.linux.namespaces);

    // 3. Unshare CLONE_NEWUTS
    // - Change hostname
    try utils.setupNamespace(.uts, runtime_config.linux.namespaces);
    if (runtime_config.hostname) |hostname| {
        try syscall.sethostname(hostname);
    }

    // 4. Unshare CLONE_NEWNET
    // - Back to old network namespace
    // - Set up network
    // - Enter new network namespace
    try utils.setupNamespace(.network, runtime_config.linux.namespaces);

    // 5. Unshare CLONE_NEWNS
    // - Prepare rootfs (Mount private, generate files ...)
    // - Mount dirs to rootfs
    // - Create devices
    // - Chroot
    try utils.setupNamespace(.mount, runtime_config.linux.namespaces);
    try rootfs.setup(alloc, &runtime_config);

    // 6. Finalize
    // - sysctl
    // - change user
    // - exec
    try process.execute(alloc, &runtime_config);

    unreachable;
}

pub fn main() !void {
    if (try zrun()) |child| {
        // Wait child outside zrun() to make sure all using memory released
        try child.wait();
    }
}
