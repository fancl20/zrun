const std = @import("std");

const CloneError = error{
    SystemResources,
    InvalidExe,
    AccessDenied,
} || std.os.UnexpectedError;

pub const clone_args = extern struct {
    flags: u64, // Flags bit mask
    pidfd: u64, // Where to store PID file descriptor (pid_t *)
    child_tid: u64, // Where to store child TID, in child's memory (pid_t *)
    parent_tid: u64, // Where to store child TID, in parent's memory (int *)
    exit_signal: u64, // Signal to deliver to parent on child termination
    stack: u64, // Pointer to lowest byte of stack
    stack_size: u64, // Size of stack
    tls: u64, // Location of new TLS
    set_tid: u64, // Pointer to a pid_t array (since Linux 5.5)
    set_tid_size: u64, // Number of elements in set_tid (since Linux 5.5)
    cgroup: u64, // File descriptor for target cgroup of child (since Linux 5.7)
};

pub const CLONE = struct {
    pub const NEWTIME = 0x00000080;
    pub const VM = 0x00000100;
    pub const FS = 0x00000200;
    pub const FILES = 0x00000400;
    pub const SIGHAND = 0x00000800;
    pub const PIDFD = 0x00001000;
    pub const PTRACE = 0x00002000;
    pub const VFORK = 0x00004000;
    pub const PARENT = 0x00008000;
    pub const THREAD = 0x00010000;
    pub const NEWNS = 0x00020000;
    pub const SYSVSEM = 0x00040000;
    pub const SETTLS = 0x00080000;
    pub const PARENT_SETTID = 0x00100000;
    pub const CHILD_CLEARTID = 0x00200000;
    pub const DETACHED = 0x00400000;
    pub const UNTRACED = 0x00800000;
    pub const CHILD_SETTID = 0x01000000;
    pub const NEWCGROUP = 0x02000000;
    pub const NEWUTS = 0x04000000;
    pub const NEWIPC = 0x08000000;
    pub const NEWUSER = 0x10000000;
    pub const NEWPID = 0x20000000;
    pub const NEWNET = 0x40000000;
    pub const IO = 0x80000000;
};

pub fn clone3(cl_args: *clone_args) CloneError!std.os.pid_t {
    const pid = std.os.linux.syscall2(.clone3, @ptrToInt(cl_args), @sizeOf(clone_args));
    return switch (std.os.errno(pid)) {
        .SUCCESS => @intCast(std.os.pid_t, @bitCast(isize, pid)),
        .AGAIN => error.SystemResources,
        .BUSY => error.SystemResources,
        .EXIST => error.SystemResources,
        .INVAL => error.InvalidExe,
        .NOMEM => return error.SystemResources,
        .NOSPC => return error.SystemResources,
        .OPNOTSUPP => return error.SystemResources,
        .PERM => error.AccessDenied,
        .USERS => return error.SystemResources,
        else => |err| std.os.unexpectedErrno(err),
    };
}

const PollError = error{
    InvalidExe,
    SystemResources,
} || std.os.UnexpectedError;

pub fn poll(fds: []std.os.pollfd, n: std.os.nfds_t, timeout: i32) PollError!usize {
    while (true) {
        const events = std.os.linux.syscall3(.poll, @ptrToInt(fds.ptr), n, @bitCast(u32, timeout));
        return switch (std.os.errno(events)) {
            .SUCCESS => events,
            .FAULT => unreachable,
            .INTR => continue,
            .INVAL => error.InvalidExe,
            .NOMEM => return error.SystemResources,
            else => |err| std.os.unexpectedErrno(err),
        };
    }
}

const PidfdOpenError = error{
    InvalidExe,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    NoDevice,
    SystemResources,
    ProcessNotFound,
} || std.os.UnexpectedError;

pub fn pidfd_open(pid: std.os.pid_t, flags: u32) !i32 {
    const pidfd = std.os.linux.syscall2(.pidfd_open, @bitCast(u32, pid), flags);
    return switch (std.os.errno(pidfd)) {
        .SUCCESS => @intCast(i32, @bitCast(isize, pidfd)),
        .INVAL => error.InvalidExe,
        .MFILE => error.ProcessFdQuotaExceeded,
        .NFILE => error.SystemFdQuotaExceeded,
        .NODEV => error.NoDevice,
        .NOMEM => error.SystemResources,
        .SRCH => error.ProcessNotFound,
        else => |err| std.os.unexpectedErrno(err),
    };
}

const SetnsError = error{
    FileDescriptorInvalid,
    InvalidExe,
    SystemResources,
    AccessDenied,
    ProcessNotFound,
} || std.os.UnexpectedError;

pub fn setns(fd: std.os.fd_t, nstype: usize) SetnsError!void {
    return switch (std.os.errno(std.os.linux.syscall2(.setns, @bitCast(u32, fd), nstype))) {
        .SUCCESS => {},
        .BADF => error.FileDescriptorInvalid,
        .INVAL => error.InvalidExe,
        .NOMEM => error.SystemResources,
        .PERM => error.AccessDenied,
        .SRCH => error.ProcessNotFound,
        else => |err| std.os.unexpectedErrno(err),
    };
}

const UnshareError = error{
    InvalidExe,
    SystemResources,
    AccessDenied,
} || std.os.UnexpectedError;

pub fn unshare(flags: usize) UnshareError!void {
    return switch (std.os.errno(std.os.linux.syscall1(.unshare, flags))) {
        .SUCCESS => {},
        .INVAL => error.InvalidExe,
        .NOMEM => error.SystemResources,
        .NOSPC => error.SystemResources,
        .PERM => error.AccessDenied,
        .USERS => error.SystemResources,
        else => |err| std.os.unexpectedErrno(err),
    };
}

const MountError = error{
    AccessDenied,
    DeviceBusy,
    InvalidExe,
    FileSystem,
    SystemResources,
    NameTooLong,
    FileNotFound,
    NotBlockDevice,
    NotDir,
    ReadOnlyFileSystem,
} || std.os.UnexpectedError;

pub fn mount(special: ?[*:0]const u8, dir: [*:0]const u8, fstype: ?[*:0]const u8, flags: u32, data: ?*u8) MountError!void {
    return switch (std.os.errno(std.os.linux.syscall5(.mount, @ptrToInt(special), @ptrToInt(dir), @ptrToInt(fstype), flags, @ptrToInt(data)))) {
        .SUCCESS => {},
        .ACCES => error.AccessDenied,
        .BUSY => error.DeviceBusy,
        .FAULT => unreachable,
        .INVAL => error.InvalidExe,
        .LOOP => error.FileSystem,
        .MFILE => error.SystemResources,
        .NAMETOOLONG => error.NameTooLong,
        .NODEV => error.SystemResources,
        .NOENT => error.FileNotFound,
        .NOMEM => error.SystemResources,
        .NOTBLK => error.NotBlockDevice,
        .NOTDIR => error.NotDir,
        .NXIO => error.InvalidExe,
        .PERM => error.AccessDenied,
        .ROFS => error.ReadOnlyFileSystem,
        else => |err| std.os.unexpectedErrno(err),
    };
}

const UmountError = error{
    WouldBlock,
    DeviceBusy,
    InvalidExe,
    NameTooLong,
    FileNotFound,
    SystemResources,
    AccessDenied,
} || std.os.UnexpectedError;

pub fn umount2(special: [*:0]const u8, flags: u32) UmountError!void {
    return switch (std.os.errno(std.os.linux.syscall2(.umount2, @ptrToInt(special), flags))) {
        .SUCCESS => {},
        .AGAIN => error.WouldBlock,
        .BUSY => error.DeviceBusy,
        .FAULT => unreachable,
        .INVAL => error.InvalidExe,
        .NAMETOOLONG => error.NameTooLong,
        .NOENT => error.FileNotFound,
        .NOMEM => error.SystemResources,
        .PERM => error.AccessDenied,
        else => |err| std.os.unexpectedErrno(err),
    };
}

const MknodError = error{
    AccessDenied,
    DiskQuota,
    PathAlreadyExists,
    InvalidExe,
    FileSystem,
    NameTooLong,
    FileNotFound,
    SystemResources,
    NoSpaceLeft,
    NotDir,
} || std.os.UnexpectedError;

pub fn mknod(pathname: [*:0]const u8, mode: std.os.linux.mode_t, dev: std.os.linux.dev_t) MknodError!void {
    return switch (std.os.errno(std.os.linux.syscall3(.mknod, @ptrToInt(pathname), mode, dev))) {
        .SUCCESS => {},
        .ACCES => error.AccessDenied,
        .DQUOT => error.DiskQuota,
        .EXIST => error.PathAlreadyExists,
        .FAULT => unreachable,
        .INVAL => error.InvalidExe,
        .LOOP => error.FileSystem,
        .NAMETOOLONG => error.NameTooLong,
        .NOENT => error.FileNotFound,
        .NOMEM => error.SystemResources,
        .NOSPC => error.NoSpaceLeft,
        .NOTDIR => error.NotDir,
        .PERM => error.AccessDenied,
        else => |err| std.os.unexpectedErrno(err),
    };
}

const ChrootError = error{
    AccessDenied,
    FileSystem,
    NameTooLong,
    FileNotFound,
    SystemResources,
    NotDir,
} || std.os.UnexpectedError;

pub fn chroot(pathname: [*:0]const u8) ChrootError!void {
    return switch (std.os.errno(std.os.linux.syscall1(.chroot, @ptrToInt(pathname)))) {
        .SUCCESS => {},
        .ACCES => error.AccessDenied,
        .FAULT => unreachable,
        .IO => error.FileSystem,
        .LOOP => error.FileSystem,
        .NAMETOOLONG => error.NameTooLong,
        .NOENT => error.FileNotFound,
        .NOMEM => error.SystemResources,
        .NOTDIR => error.NotDir,
        .PERM => error.AccessDenied,
        else => |err| std.os.unexpectedErrno(err),
    };
}

const ChownError = error{
    AccessDenied,
    FileSystem,
    NameTooLong,
    FileNotFound,
    SystemResources,
    NotDir,
    ReadOnlyFileSystem,
} || std.os.UnexpectedError;

pub fn chown(pathname: [*:0]const u8, uid: std.os.linux.uid_t, gid: std.os.linux.gid_t) ChownError!void {
    return switch (std.os.errno(std.os.linux.syscall3(.chown, @ptrToInt(pathname), uid, gid))) {
        .SUCCESS => {},
        .ACCES => error.AccessDenied,
        .FAULT => unreachable,
        .LOOP => error.FileSystem,
        .NAMETOOLONG => error.NameTooLong,
        .NOENT => error.FileNotFound,
        .NOMEM => error.SystemResources,
        .NOTDIR => error.NotDir,
        .PERM => error.AccessDenied,
        .ROFS => error.ReadOnlyFileSystem,
        else => |err| std.os.unexpectedErrno(err),
    };
}

const SethostnameError = error{
    InvalidExe,
    NameTooLong,
    AccessDenied,
} || std.os.UnexpectedError;

pub fn sethostname(name: []const u8) SethostnameError!void {
    return switch (std.os.errno(std.os.linux.syscall2(.sethostname, @ptrToInt(name.ptr), name.len))) {
        .SUCCESS => {},
        .FAULT => unreachable,
        .INVAL => error.InvalidExe,
        .NAMETOOLONG => error.NameTooLong,
        .PERM => error.AccessDenied,
        else => |err| std.os.unexpectedErrno(err),
    };
}

pub fn mkdev(major: u64, minor: u64) std.os.linux.dev_t {
    var dev: std.os.linux.dev_t = 0;
    dev |= (major & 0x00000fff) << 8;
    dev |= (major & 0xfffff000) << 32;
    dev |= (minor & 0x000000ff) << 0;
    dev |= (minor & 0xffffff00) << 12;
    return dev;
}

pub fn umask(mask: std.os.mode_t) std.os.mode_t {
    return std.os.linux.syscall1(.umask, mask);
}

const SetgroupsError = error{
    InvalidExe,
    SystemResources,
    AccessDenied,
} || std.os.UnexpectedError;

pub fn setgroups(list: []std.os.gid_t) SetgroupsError!usize {
    const nums = std.os.linux.syscall2(.setgroups, list.len, @ptrToInt(list.ptr));
    return switch (std.os.errno(nums)) {
        .SUCCESS => nums,
        .FAULT => unreachable,
        .INVAL => error.InvalidExe,
        .NOMEM => error.SystemResources,
        .PERM => error.AccessDenied,
        else => |err| std.os.unexpectedErrno(err),
    };
}
