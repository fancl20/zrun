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

pub const CLONE_NEWTIME = 0x00000080;
pub const CLONE_VM = 0x00000100;
pub const CLONE_FS = 0x00000200;
pub const CLONE_FILES = 0x00000400;
pub const CLONE_SIGHAND = 0x00000800;
pub const CLONE_PIDFD = 0x00001000;
pub const CLONE_PTRACE = 0x00002000;
pub const CLONE_VFORK = 0x00004000;
pub const CLONE_PARENT = 0x00008000;
pub const CLONE_THREAD = 0x00010000;
pub const CLONE_NEWNS = 0x00020000;
pub const CLONE_SYSVSEM = 0x00040000;
pub const CLONE_SETTLS = 0x00080000;
pub const CLONE_PARENT_SETTID = 0x00100000;
pub const CLONE_CHILD_CLEARTID = 0x00200000;
pub const CLONE_DETACHED = 0x00400000;
pub const CLONE_UNTRACED = 0x00800000;
pub const CLONE_CHILD_SETTID = 0x01000000;
pub const CLONE_NEWCGROUP = 0x02000000;
pub const CLONE_NEWUTS = 0x04000000;
pub const CLONE_NEWIPC = 0x08000000;
pub const CLONE_NEWUSER = 0x10000000;
pub const CLONE_NEWPID = 0x20000000;
pub const CLONE_NEWNET = 0x40000000;
pub const CLONE_IO = 0x80000000;

pub fn clone3(cl_args: *clone_args) CloneError!std.os.pid_t {
    const pid = std.os.linux.syscall2(.clone3, @ptrToInt(cl_args), @sizeOf(clone_args));
    return switch (std.os.errno(pid)) {
        0 => @intCast(std.os.pid_t, @bitCast(isize, pid)),
        std.os.linux.EAGAIN => error.SystemResources,
        std.os.linux.EBUSY => error.SystemResources,
        std.os.linux.EEXIST => error.SystemResources,
        std.os.linux.EINVAL => error.InvalidExe,
        std.os.linux.ENOMEM => return error.SystemResources,
        std.os.linux.ENOSPC => return error.SystemResources,
        std.os.linux.EOPNOTSUPP => return error.SystemResources,
        std.os.linux.EPERM => error.AccessDenied,
        std.os.linux.EUSERS => return error.SystemResources,
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
            0 => events,
            std.os.linux.EFAULT => unreachable,
            std.os.linux.EINTR => continue,
            std.os.linux.EINVAL => error.InvalidExe,
            std.os.linux.ENOMEM => return error.SystemResources,
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
        0 => @intCast(i32, @bitCast(isize, pidfd)),
        std.os.linux.EINVAL => error.InvalidExe,
        std.os.linux.EMFILE => error.ProcessFdQuotaExceeded,
        std.os.linux.ENFILE => error.SystemFdQuotaExceeded,
        std.os.linux.ENODEV => error.NoDevice,
        std.os.linux.ENOMEM => error.SystemResources,
        std.os.linux.ESRCH => error.ProcessNotFound,
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
        0 => {},
        std.os.linux.EINVAL => error.InvalidExe,
        std.os.linux.ENOMEM => error.SystemResources,
        std.os.linux.ENOSPC => error.SystemResources,
        std.os.linux.EPERM => error.AccessDenied,
        std.os.linux.EUSERS => error.SystemResources,
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
        0 => {},
        std.os.linux.EACCES => error.AccessDenied,
        std.os.linux.EBUSY => error.DeviceBusy,
        std.os.linux.EFAULT => unreachable,
        std.os.linux.EINVAL => error.InvalidExe,
        std.os.linux.ELOOP => error.FileSystem,
        std.os.linux.EMFILE => error.SystemResources,
        std.os.linux.ENAMETOOLONG => error.NameTooLong,
        std.os.linux.ENODEV => error.SystemResources,
        std.os.linux.ENOENT => error.FileNotFound,
        std.os.linux.ENOMEM => error.SystemResources,
        std.os.linux.ENOTBLK => error.NotBlockDevice,
        std.os.linux.ENOTDIR => error.NotDir,
        std.os.linux.ENXIO => error.InvalidExe,
        std.os.linux.EPERM => error.AccessDenied,
        std.os.linux.EROFS => error.ReadOnlyFileSystem,
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
        0 => {},
        std.os.linux.EAGAIN => error.WouldBlock,
        std.os.linux.EBUSY => error.DeviceBusy,
        std.os.linux.EFAULT => unreachable,
        std.os.linux.EINVAL => error.InvalidExe,
        std.os.linux.ENAMETOOLONG => error.NameTooLong,
        std.os.linux.ENOENT => error.FileNotFound,
        std.os.linux.ENOMEM => error.SystemResources,
        std.os.linux.EPERM => error.AccessDenied,
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
        0 => {},
        std.os.linux.EACCES => error.AccessDenied,
        std.os.linux.EDQUOT => error.DiskQuota,
        std.os.linux.EEXIST => error.PathAlreadyExists,
        std.os.linux.EFAULT => unreachable,
        std.os.linux.EINVAL => error.InvalidExe,
        std.os.linux.ELOOP => error.FileSystem,
        std.os.linux.ENAMETOOLONG => error.NameTooLong,
        std.os.linux.ENOENT => error.FileNotFound,
        std.os.linux.ENOMEM => error.SystemResources,
        std.os.linux.ENOSPC => error.NoSpaceLeft,
        std.os.linux.ENOTDIR => error.NotDir,
        std.os.linux.EPERM => error.AccessDenied,
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
        0 => {},
        std.os.linux.EACCES => error.AccessDenied,
        std.os.linux.EFAULT => unreachable,
        std.os.linux.EIO => error.FileSystem,
        std.os.linux.ELOOP => error.FileSystem,
        std.os.linux.ENAMETOOLONG => error.NameTooLong,
        std.os.linux.ENOENT => error.FileNotFound,
        std.os.linux.ENOMEM => error.SystemResources,
        std.os.linux.ENOTDIR => error.NotDir,
        std.os.linux.EPERM => error.AccessDenied,
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
        0 => {},
        std.os.linux.EACCES => error.AccessDenied,
        std.os.linux.EFAULT => unreachable,
        std.os.linux.ELOOP => error.FileSystem,
        std.os.linux.ENAMETOOLONG => error.NameTooLong,
        std.os.linux.ENOENT => error.FileNotFound,
        std.os.linux.ENOMEM => error.SystemResources,
        std.os.linux.ENOTDIR => error.NotDir,
        std.os.linux.EPERM => error.AccessDenied,
        std.os.linux.EROFS => error.ReadOnlyFileSystem,
        else => |err| std.os.unexpectedErrno(err),
    };
}

const SetHostnameError = error{
    InvalidExe,
    NameTooLong,
    AccessDenied,
} || std.os.UnexpectedError;

pub fn sethostname(name: []const u8) SetHostnameError!void {
    return switch (std.os.errno(std.os.linux.syscall2(.sethostname, @ptrToInt(name.ptr), name.len))) {
        0 => {},
        std.os.linux.EFAULT => unreachable,
        std.os.linux.EINVAL => error.InvalidExe,
        std.os.linux.ENAMETOOLONG => error.NameTooLong,
        std.os.linux.EPERM => error.AccessDenied,
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
