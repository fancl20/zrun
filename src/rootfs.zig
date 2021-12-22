const std = @import("std");
const runtime_spec = @import("runtime_spec.zig");
const syscall = @import("syscall.zig");
const utils = @import("utils.zig");

const linux = std.os.linux;

const RootfsSetupError = error{ MountParentPrivateFailed, InvalidDeviceType, InvalidRootfsPropagation };

fn makeParentMountPrivate(alloc: std.mem.Allocator, rootfs: [:0]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var parent = try arena.allocator().dupeZ(u8, rootfs);
    while (true) {
        if (syscall.mount(null, parent, null, linux.MS.PRIVATE, null)) |_| {
            return;
        } else |_| if (std.fs.path.dirname(parent)) |dir| {
            parent[dir.len] = 0;
            parent = parent[0..dir.len :0];
        } else {
            return RootfsSetupError.MountParentPrivateFailed;
        }
    }
    unreachable();
}

fn prepare(alloc: std.mem.Allocator, rootfs: [:0]const u8) !void {
    try makeParentMountPrivate(alloc, rootfs);
    try syscall.mount(rootfs, rootfs, null, linux.MS.BIND | linux.MS.REC, null);
    try syscall.mount(null, rootfs, null, linux.MS.PRIVATE, null);
}

fn updateMountFlags(current_flags: u32, name: []const u8) ?u32 {
    if (std.mem.eql(u8, name, "bind")) return current_flags | linux.MS.BIND;
    if (std.mem.eql(u8, name, "rbind")) return current_flags | linux.MS.REC | linux.MS.BIND;
    if (std.mem.eql(u8, name, "ro")) return current_flags | linux.MS.RDONLY;
    if (std.mem.eql(u8, name, "rw")) return current_flags & ~@intCast(u32, linux.MS.RDONLY);
    if (std.mem.eql(u8, name, "suid")) return current_flags & ~@intCast(u32, linux.MS.NOSUID);
    if (std.mem.eql(u8, name, "nosuid")) return current_flags | linux.MS.NOSUID;
    if (std.mem.eql(u8, name, "dev")) return current_flags & ~@intCast(u32, linux.MS.NODEV);
    if (std.mem.eql(u8, name, "nodev")) return current_flags | linux.MS.NODEV;
    if (std.mem.eql(u8, name, "exec")) return current_flags & ~@intCast(u32, linux.MS.NOEXEC);
    if (std.mem.eql(u8, name, "noexec")) return current_flags | linux.MS.NOEXEC;
    if (std.mem.eql(u8, name, "sync")) return current_flags | linux.MS.SYNCHRONOUS;
    if (std.mem.eql(u8, name, "async")) return current_flags & ~@intCast(u32, linux.MS.SYNCHRONOUS);
    if (std.mem.eql(u8, name, "dirsync")) return current_flags | linux.MS.DIRSYNC;
    if (std.mem.eql(u8, name, "remount")) return current_flags | linux.MS.REMOUNT;
    if (std.mem.eql(u8, name, "mand")) return current_flags | linux.MS.MANDLOCK;
    if (std.mem.eql(u8, name, "nomand")) return current_flags & ~@intCast(u32, linux.MS.MANDLOCK);
    if (std.mem.eql(u8, name, "atime")) return current_flags & ~@intCast(u32, linux.MS.NOATIME);
    if (std.mem.eql(u8, name, "noatime")) return current_flags | linux.MS.NOATIME;
    if (std.mem.eql(u8, name, "diratime")) return current_flags & ~@intCast(u32, linux.MS.NODIRATIME);
    if (std.mem.eql(u8, name, "nodiratime")) return current_flags | linux.MS.NODIRATIME;
    if (std.mem.eql(u8, name, "relatime")) return current_flags | linux.MS.RELATIME;
    if (std.mem.eql(u8, name, "norelatime")) return current_flags & ~@intCast(u32, linux.MS.RELATIME);
    if (std.mem.eql(u8, name, "strictatime")) return current_flags | linux.MS.STRICTATIME;
    if (std.mem.eql(u8, name, "nostrictatime")) return current_flags & ~@intCast(u32, linux.MS.STRICTATIME);
    if (std.mem.eql(u8, name, "shared")) return current_flags | linux.MS.SHARED;
    if (std.mem.eql(u8, name, "rshared")) return current_flags | linux.MS.REC | linux.MS.SHARED;
    if (std.mem.eql(u8, name, "slave")) return current_flags | linux.MS.SLAVE;
    if (std.mem.eql(u8, name, "rslave")) return current_flags | linux.MS.REC | linux.MS.SLAVE;
    if (std.mem.eql(u8, name, "private")) return current_flags | linux.MS.PRIVATE;
    if (std.mem.eql(u8, name, "rprivate")) return current_flags | linux.MS.REC | linux.MS.PRIVATE;
    if (std.mem.eql(u8, name, "unbindable")) return current_flags | linux.MS.UNBINDABLE;
    if (std.mem.eql(u8, name, "runbindable")) return current_flags | linux.MS.REC | linux.MS.UNBINDABLE;
    return null;
}

fn doMounts(alloc: std.mem.Allocator, rootfs: [:0]const u8, mounts: []runtime_spec.Mount) !void {
    for (mounts) |m| {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();

        var flags: u32 = 0;
        var opts = try std.ArrayList([]const u8).initCapacity(arena.allocator(), m.options.len);
        for (m.options) |opt| {
            if (updateMountFlags(flags, opt)) |new_flags| {
                flags = new_flags;
            } else {
                opts.appendAssumeCapacity(opt);
            }
        }
        const dest = try std.fs.path.join(arena.allocator(), &[_][]const u8{ rootfs, m.destination });
        try utils.mkdirs(dest, 0o755);
        try syscall.mount(
            try arena.allocator().dupeZ(u8, m.source),
            try arena.allocator().dupeZ(u8, dest),
            try arena.allocator().dupeZ(u8, m.type),
            flags,
            @ptrCast(*u8, try std.mem.joinZ(arena.allocator(), ",", opts.items)),
        );
    }
}

const DeviceType = enum(u8) {
    BlockDevice = 'b',
    CharDevice = 'c',
    FifoDevice = 'p',
    _,
};

fn getDeviceFileModeFromType(device_type: []u8) RootfsSetupError!u32 {
    if (device_type.len != 1) {
        return error.InvalidDeviceType;
    }
    return switch (@intToEnum(DeviceType, device_type[0])) {
        .BlockDevice => linux.S.IFBLK,
        .CharDevice => linux.S.IFCHR,
        .FifoDevice => linux.S.IFIFO,
        _ => error.InvalidDeviceType,
    };
}

fn createDevices(alloc: std.mem.Allocator, rootfs: [:0]const u8, devices: []runtime_spec.LinuxDevice) !void {
    for (devices) |d| {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();

        const dest = try std.fs.path.joinZ(arena.allocator(), &[_][]const u8{ rootfs, d.path });
        const file_mode: linux.mode_t = d.fileMode | try getDeviceFileModeFromType(d.type);
        const dev = syscall.mkdev(d.major, d.minor);
        try syscall.mknod(dest, file_mode, dev);
        try syscall.chown(dest, d.uid, d.gid);
    }
}

fn moveChroot(rootfs: [:0]const u8) !void {
    try std.os.chdir(rootfs);
    try syscall.mount(rootfs, "/", null, linux.MS.MOVE, null);
    try syscall.chroot(".");
    try std.os.chdir("/");
}

pub fn setup(alloc: std.mem.Allocator, spec: *const runtime_spec.Spec) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    const rootfs = try utils.realpathAllocZ(arena.allocator(), spec.root.path);

    // Remount old rootfs before we preparing new rootfs to prevent leaking mounts outside namespace
    var rootfs_propagation: u32 = linux.MS.REC | linux.MS.PRIVATE;
    if (spec.linux.rootfsPropagation) |propagation| {
        rootfs_propagation = updateMountFlags(0, propagation) orelse 0;
    }
    if (rootfs_propagation & (linux.MS.SHARED | linux.MS.SLAVE | linux.MS.PRIVATE | linux.MS.UNBINDABLE) == 0) {
        return RootfsSetupError.InvalidRootfsPropagation;
    }
    try syscall.mount(null, "/", null, rootfs_propagation, null);

    try prepare(alloc, rootfs);
    try doMounts(alloc, rootfs, spec.mounts);
    try createDevices(alloc, rootfs, spec.linux.devices);
    try moveChroot(rootfs);
    if (spec.root.readonly) {
        try syscall.mount(null, "/", null, linux.MS.REMOUNT | linux.MS.BIND | linux.MS.RDONLY, null);
    }
}
