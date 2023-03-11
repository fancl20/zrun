const std = @import("std");
const runtime_spec = @import("runtime_spec.zig");
const syscall = @import("syscall.zig");

pub fn realpathAllocZ(alloc: std.mem.Allocator, pathname: []const u8) ![:0]u8 {
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

        pub fn init(alloc: std.mem.Allocator, slice: []const u8) !Self {
            var tokenStream = std.json.TokenStream.init(slice);
            var option = std.json.ParseOptions{ .allocator = alloc };
            return Self{
                .parseOption = option,
                .value = try std.json.parse(T, &tokenStream, option),
            };
        }
        pub fn initFromFile(alloc: std.mem.Allocator, path: []const u8) !Self {
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

fn waitPidfd(pidfd: i32, timeout: i32) !bool {
    const exited = try syscall.poll(&[_]std.os.pollfd{.{
        .fd = pidfd,
        .events = std.os.POLL.IN,
        .revents = 0,
    }}, 1, timeout);
    return exited != 0;
}

pub const Process = struct {
    id: std.os.pid_t,
    fd: std.os.fd_t,
    detach: bool,

    pub fn wait(self: *const Process) !void {
        if (!self.detach) {
            _ = try waitPidfd(self.fd, -1);
        }
    }
    pub fn createPidFile(self: *const Process, pid_file: []const u8) !void {
        var f = try std.fs.createFileAbsolute(pid_file, .{ .exclusive = true, .mode = 0o644 });
        defer f.close();
        try std.fmt.format(f.writer(), "{}", .{self.id});
    }
};

pub fn fork(detach: bool) !?Process {
    const ppidfd = try syscall.pidfd_open(std.os.linux.getpid(), 0);
    var pidfd: i32 = -1;
    var cloneArgs = syscall.clone_args{
        .flags = syscall.CLONE.PIDFD,
        .pidfd = @ptrToInt(&pidfd),
        .child_tid = 0,
        .parent_tid = 0,
        .exit_signal = 0,
        .stack = 0,
        .stack_size = 0,
        .tls = 0,
        .set_tid = 0,
        .set_tid_size = 0,
        .cgroup = 0,
    };
    const pid = try syscall.clone3(&cloneArgs);
    if (pid != 0) {
        return Process{ .id = pid, .fd = pidfd, .detach = detach };
    }
    if (!detach) {
        _ = try std.os.prctl(.SET_PDEATHSIG, .{std.os.linux.SIG.KILL});
        if (try waitPidfd(ppidfd, 0)) {
            // Exit if parent process exited before child process ready.
            std.os.exit(0);
        }
    }
    return null;
}

pub const Namespace = enum(usize) {
    pid = syscall.CLONE.NEWPID,
    network = syscall.CLONE.NEWNET,
    ipc = syscall.CLONE.NEWIPC,
    uts = syscall.CLONE.NEWUTS,
    mount = syscall.CLONE.NEWNS,
};

pub fn setupNamespace(namespace: Namespace, config: []runtime_spec.LinuxNamespace) !void {
    for (config) |namespace_config| {
        if (std.mem.eql(u8, @tagName(namespace), namespace_config.type)) {
            if (namespace_config.path) |path| {
                const fd = try std.os.open(path, std.os.O.RDONLY | std.os.O.CLOEXEC, 0);
                defer std.os.close(fd);
                try syscall.setns(fd, @enumToInt(namespace));
            } else {
                try syscall.unshare(@enumToInt(namespace));
            }
            return;
        }
    }
    return;
}

const SpecError = error{UnknowNamespace};

pub fn validateSpec(spec: *const runtime_spec.Spec) SpecError!void {
    for (spec.linux.namespaces) |namespace_config| {
        var valid = false;
        inline for (@typeInfo(Namespace).Enum.fields) |filed| {
            if (std.mem.eql(u8, filed.name, namespace_config.type)) {
                valid = true;
            }
        }
        if (!valid) {
            return error.UnknowNamespace;
        }
    }
    return;
}
