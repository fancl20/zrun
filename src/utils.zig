const std = @import("std");

const UnshareError = error{
    InvalidExe,
    SystemResources,
    AccessDenied,
} || std.os.UnexpectedError;

pub fn unshare(flags: usize) UnshareError!void {
    switch (std.os.errno(std.os.linux.syscall1(.unshare, flags))) {
        0 => return,
        std.os.linux.EINVAL => return error.InvalidExe,
        std.os.linux.ENOMEM => return error.SystemResources,
        std.os.linux.ENOSPC => return error.SystemResources,
        std.os.linux.EPERM => return error.AccessDenied,
        std.os.linux.EUSERS => return error.SystemResources,
        else => |err| return std.os.unexpectedErrno(err),
    }
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
    switch (std.os.errno(std.os.linux.syscall5(.mount, @ptrToInt(special), @ptrToInt(dir), @ptrToInt(fstype), flags, @ptrToInt(data)))) {
        0 => return,
        std.os.linux.EACCES => return error.AccessDenied,
        std.os.linux.EBUSY => return error.DeviceBusy,
        std.os.linux.EFAULT => unreachable,
        std.os.linux.EINVAL => return error.InvalidExe,
        std.os.linux.ELOOP => return error.FileSystem,
        std.os.linux.EMFILE => return error.SystemResources,
        std.os.linux.ENAMETOOLONG => return error.NameTooLong,
        std.os.linux.ENODEV => return error.SystemResources,
        std.os.linux.ENOENT => return error.FileNotFound,
        std.os.linux.ENOMEM => return error.SystemResources,
        std.os.linux.ENOTBLK => return error.NotBlockDevice,
        std.os.linux.ENOTDIR => return error.NotDir,
        std.os.linux.ENXIO => return error.InvalidExe,
        std.os.linux.EPERM => return error.AccessDenied,
        std.os.linux.EROFS => return error.ReadOnlyFileSystem,
        else => |err| return std.os.unexpectedErrno(err),
    }
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
    switch (std.os.errno(std.os.linux.syscall2(.umount2, @ptrToInt(special), flags))) {
        0 => return,
        std.os.linux.EAGAIN => return error.WouldBlock,
        std.os.linux.EBUSY => return error.DeviceBusy,
        std.os.linux.EFAULT => unreachable,
        std.os.linux.EINVAL => return error.InvalidExe,
        std.os.linux.ENAMETOOLONG => return error.NameTooLong,
        std.os.linux.ENOENT => return error.FileNotFound,
        std.os.linux.ENOMEM => return error.SystemResources,
        std.os.linux.EPERM => return error.AccessDenied,
        else => |err| return std.os.unexpectedErrno(err),
    }
}

const ChrootError = error{
    AccessDenied,
    FileSystem,
    NameTooLong,
    FileNotFound,
    SystemResources,
    NotDir,
} || std.os.UnexpectedError;

pub fn chroot(path: [*:0]const u8) ChrootError!void {
    switch (std.os.errno(std.os.linux.syscall1(.chroot, @ptrToInt(path)))) {
        0 => return,
        std.os.linux.EACCES => return error.AccessDenied,
        std.os.linux.EFAULT => unreachable,
        std.os.linux.EIO => return error.FileSystem,
        std.os.linux.ELOOP => return error.FileSystem,
        std.os.linux.ENAMETOOLONG => return error.NameTooLong,
        std.os.linux.ENOENT => return error.FileNotFound,
        std.os.linux.ENOMEM => return error.SystemResources,
        std.os.linux.ENOTDIR => return error.NotDir,
        std.os.linux.EPERM => return error.AccessDenied,
        else => |err| return std.os.unexpectedErrno(err),
    }
}

const SetHostnameError = error{
    InvalidExe,
    NameTooLong,
    AccessDenied,
} || std.os.UnexpectedError;

pub fn sethostname(name: []const u8) !void {
    switch (std.os.errno(std.os.linux.syscall2(.sethostname, @ptrToInt(name.ptr), name.len))) {
        0 => return,
        std.os.linux.EFAULT => unreachable,
        std.os.linux.EINVAL => return error.InvalidExe,
        std.os.linux.ENAMETOOLONG => return error.NameTooLong,
        std.os.linux.EPERM => return error.AccessDenied,
        else => |err| return std.os.unexpectedErrno(err),
    }
}

pub fn realpathAllocZ(alloc: *std.mem.Allocator, pathname: []const u8) ![:0]u8 {
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    return alloc.dupeZ(u8, try std.fs.cwd().realpath(pathname, buf[0..]));
}

pub fn mkdirs(pathname: []const u8, mode: u32) std.os.MakeDirError!void {
    if (std.os.access(pathname, std.os.F_OK)) |_| {
        return;
    } else |_| {}
    try mkdirs(std.fs.path.dirname(pathname).?, mode);
    try std.os.mkdir(pathname, mode);
}

pub fn ptrZtoSlice(ptr: [*:0]u8) [:0]u8 {
    return ptr[0..std.mem.lenZ(ptr) :0];
}

pub fn JsonLoader(comptime T: type) type {
    return struct {
        const Self = @This();

        parseOption: std.json.ParseOptions,
        value: T,

        pub fn init(alloc: *std.mem.Allocator, slice: []const u8) !Self {
            var option = std.json.ParseOptions{ .allocator = alloc };
            return Self{
                .parseOption = option,
                .value = try std.json.parse(T, &std.json.TokenStream.init(slice), option),
            };
        }
        pub fn initFromFile(alloc: *std.mem.Allocator, path: []const u8) !Self {
            var file = try std.fs.cwd().openFile(path, .{});
            var content = try file.readToEndAlloc(alloc, 65535);
            defer alloc.free(content);
            return Self.init(alloc, content);
        }
        pub fn deinit(self: *Self) void {
            std.json.parseFree(T, self.value, self.parseOption);
        }
    };
}
