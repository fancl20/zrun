const std = @import("std");
const container = @import("container.zig");
const runtime_spec = @import("runtime_spec.zig");
const syscall = @import("syscall.zig");
const utils = @import("utils.zig");

const RootfsSetupError = error{
    MountParentPrivateFailed,
    InvalidDeviceType,
};

fn makeParentMountPrivate(alloc: *std.mem.Allocator, rootfs: [:0]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var parent = try arena.allocator.dupeZ(u8, rootfs);
    while (true) {
        if (syscall.mount(null, parent, null, std.os.linux.MS_PRIVATE, null)) |_| {
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

fn prepare(alloc: *std.mem.Allocator, rootfs: [:0]const u8) !void {
    try makeParentMountPrivate(alloc, rootfs);
    try syscall.mount(rootfs, rootfs, null, std.os.linux.MS_BIND | std.os.linux.MS_REC, null);
    try syscall.mount(null, rootfs, null, std.os.linux.MS_PRIVATE, null);
}

fn updateMountFlags(current_flags: u32, name: []const u8) ?u32 {
    if (std.mem.eql(u8, name, "bind")) return current_flags | std.os.linux.MS_BIND;
    if (std.mem.eql(u8, name, "rbind")) return current_flags | std.os.linux.MS_REC | std.os.linux.MS_BIND;
    if (std.mem.eql(u8, name, "ro")) return current_flags | std.os.linux.MS_RDONLY;
    if (std.mem.eql(u8, name, "rw")) return current_flags & ~@intCast(u32, std.os.linux.MS_RDONLY);
    if (std.mem.eql(u8, name, "suid")) return current_flags & ~@intCast(u32, std.os.linux.MS_NOSUID);
    if (std.mem.eql(u8, name, "nosuid")) return current_flags | std.os.linux.MS_NOSUID;
    if (std.mem.eql(u8, name, "dev")) return current_flags & ~@intCast(u32, std.os.linux.MS_NODEV);
    if (std.mem.eql(u8, name, "nodev")) return current_flags | std.os.linux.MS_NODEV;
    if (std.mem.eql(u8, name, "exec")) return current_flags & ~@intCast(u32, std.os.linux.MS_NOEXEC);
    if (std.mem.eql(u8, name, "noexec")) return current_flags | std.os.linux.MS_NOEXEC;
    if (std.mem.eql(u8, name, "sync")) return current_flags | std.os.linux.MS_SYNCHRONOUS;
    if (std.mem.eql(u8, name, "async")) return current_flags & ~@intCast(u32, std.os.linux.MS_SYNCHRONOUS);
    if (std.mem.eql(u8, name, "dirsync")) return current_flags | std.os.linux.MS_DIRSYNC;
    if (std.mem.eql(u8, name, "remount")) return current_flags | std.os.linux.MS_REMOUNT;
    if (std.mem.eql(u8, name, "mand")) return current_flags | std.os.linux.MS_MANDLOCK;
    if (std.mem.eql(u8, name, "nomand")) return current_flags & ~@intCast(u32, std.os.linux.MS_MANDLOCK);
    if (std.mem.eql(u8, name, "atime")) return current_flags & ~@intCast(u32, std.os.linux.MS_NOATIME);
    if (std.mem.eql(u8, name, "noatime")) return current_flags | std.os.linux.MS_NOATIME;
    if (std.mem.eql(u8, name, "diratime")) return current_flags & ~@intCast(u32, std.os.linux.MS_NODIRATIME);
    if (std.mem.eql(u8, name, "nodiratime")) return current_flags | std.os.linux.MS_NODIRATIME;
    if (std.mem.eql(u8, name, "relatime")) return current_flags | std.os.linux.MS_RELATIME;
    if (std.mem.eql(u8, name, "norelatime")) return current_flags & ~@intCast(u32, std.os.linux.MS_RELATIME);
    if (std.mem.eql(u8, name, "strictatime")) return current_flags | std.os.linux.MS_STRICTATIME;
    if (std.mem.eql(u8, name, "nostrictatime")) return current_flags & ~@intCast(u32, std.os.linux.MS_STRICTATIME);
    if (std.mem.eql(u8, name, "shared")) return current_flags | std.os.linux.MS_SHARED;
    if (std.mem.eql(u8, name, "rshared")) return current_flags | std.os.linux.MS_REC | std.os.linux.MS_SHARED;
    if (std.mem.eql(u8, name, "slave")) return current_flags | std.os.linux.MS_SLAVE;
    if (std.mem.eql(u8, name, "rslave")) return current_flags | std.os.linux.MS_REC | std.os.linux.MS_SLAVE;
    if (std.mem.eql(u8, name, "private")) return current_flags | std.os.linux.MS_PRIVATE;
    if (std.mem.eql(u8, name, "rprivate")) return current_flags | std.os.linux.MS_REC | std.os.linux.MS_PRIVATE;
    if (std.mem.eql(u8, name, "unbindable")) return current_flags | std.os.linux.MS_UNBINDABLE;
    if (std.mem.eql(u8, name, "runbindable")) return current_flags | std.os.linux.MS_REC | std.os.linux.MS_UNBINDABLE;
    return null;
}

fn doMounts(alloc: *std.mem.Allocator, rootfs: [:0]const u8, mounts: []runtime_spec.Mount) !void {
    for (mounts) |m| {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();

        var flags: u32 = 0;
        var opts = try std.ArrayList([]const u8).initCapacity(&arena.allocator, m.options.len);
        for (m.options) |opt| {
            if (updateMountFlags(flags, opt)) |new_flags| {
                flags = new_flags;
            } else {
                opts.appendAssumeCapacity(opt);
            }
        }
        const dest = try std.fs.path.join(&arena.allocator, &[_][]const u8{ rootfs, m.destination });
        try utils.mkdirs(dest, 0o755);
        try syscall.mount(
            try arena.allocator.dupeZ(u8, m.source),
            try arena.allocator.dupeZ(u8, dest),
            try arena.allocator.dupeZ(u8, m.type),
            flags,
            @ptrCast(*u8, try std.mem.joinZ(&arena.allocator, ",", opts.items)),
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
        .BlockDevice => std.os.linux.S_IFBLK,
        .CharDevice => std.os.linux.S_IFCHR,
        .FifoDevice => std.os.linux.S_IFIFO,
        _ => error.InvalidDeviceType,
    };
}

fn createDevices(alloc: *std.mem.Allocator, rootfs: [:0]const u8, devices: []runtime_spec.LinuxDevice) !void {
    for (devices) |d| {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();

        // TODO: Use fs.path.joinZ instead
        const dest = try arena.allocator.dupeZ(u8, try std.fs.path.join(&arena.allocator, &[_][]const u8{ rootfs, d.path }));
        const file_mode: std.os.linux.mode_t = d.fileMode | try getDeviceFileModeFromType(d.type);
        const dev = syscall.mkdev(d.major, d.minor);
        try syscall.mknod(dest, file_mode, dev);
        try syscall.chown(dest, d.uid, d.gid);
    }
}

fn moveChroot(rootfs: [:0]const u8) !void {
    try std.os.chdir(rootfs);
    try syscall.mount(rootfs, "/", null, std.os.linux.MS_MOVE, null);
    try syscall.chroot(".");
    try std.os.chdir("/");
}

pub fn setup(alloc: *std.mem.Allocator, spec: *const runtime_spec.Spec) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    const rootfs = try utils.realpathAllocZ(&arena.allocator, spec.root.path);

    try prepare(alloc, rootfs);
    try doMounts(alloc, rootfs, spec.mounts);
    try createDevices(alloc, rootfs, spec.linux.devices);
    try moveChroot(rootfs);
    if (spec.root.readonly) {
        try syscall.mount(null, "/", null, std.os.linux.MS_REMOUNT | std.os.linux.MS_BIND | std.os.linux.MS_RDONLY, null);
    }
}
