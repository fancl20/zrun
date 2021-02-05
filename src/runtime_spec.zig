const std = @import("std");

// Spec is the base configuration for the container.
pub const Spec = struct {
    // Process configures the container process.
    process: Process,
    // Root configures the container's root filesystem.
    root: Root,
    // Hostname configures the container's hostname.
    hostname: ?[]const u8 = null,
    // Mounts configures additional mounts (on top of Root).
    mounts: []Mount = &[_]Mount{},

    // Linux is platform-specific configuration for Linux based containers.
    linux: Linux,
};

// Process contains information to start a specific application inside the container.
pub const Process = struct {
    // TODO: Terminal creates an interactive terminal for the container.
    terminal: bool = false,
    // TODO: ConsoleSize specifies the size of the console.
    consoleSize: ?Box = null,
    // User specifies user information for the process.
    user: User,
    // Args specifies the binary and arguments for the application to execute.
    args: [][]const u8 = &[_][]const u8{},
    // Env populates the process environment for the process.
    env: [][]const u8 = &[_][]const u8{},
    // Cwd is the current working directory for the process and must be
    // relative to the container's root.
    cwd: []const u8 = "/",
};

// Box specifies dimensions of a rectangle. Used for specifying the size of a console.
pub const Box = struct {
    // Height is the vertical dimension of a box.
    height: u32,
    // Width is the horizontal dimension of a box.
    width: u32,
};

// User specifies specific user (and group) information for the container process.
pub const User = struct {
    // UID is the user id.
    uid: u32,
    // GID is the group id.
    gid: u32,
    // TODO: Umask is the umask for the init process.
    umask: ?u32 = null,
    // TODO: AdditionalGids are additional group ids set for the container's process.
    additionalGids: []u32 = &[_]u32{},
};

// Root contains information about the container's root filesystem on the host.
pub const Root = struct {
    // Path is the absolute path to the container's root filesystem.
    path: []const u8,
    // Readonly makes the root filesystem for the container readonly before the process is executed.
    readonly: bool = true,
};

// Mount specifies a mount for a container.
pub const Mount = struct {
    // Destination is the absolute path where the mount will be placed in the container.
    destination: []const u8,
    // Type specifies the mount kind.
    type: []const u8,
    // Source specifies the source path of the mount.
    source: []const u8,
    // Options are fstab style mount options.
    options: [][]const u8 = &[_][]const u8{},
};

// Linux contains platform-specific configuration for Linux based containers.
pub const Linux = struct {
    // TODO: Sysctl are a set of key value pairs that are set for the container on start
    // sysctl: std.StringHashMap([]const u8),
    // TODO: Namespaces contains the namespaces that are created and/or joined by the container
    namespaces: []LinuxNamespace = &[_]LinuxNamespace{},
    // Devices are a list of device nodes that are created for the container
    devices: []LinuxDevice = &[_]LinuxDevice{},
};

// LinuxNamespace is the configuration for a Linux namespace
pub const LinuxNamespace = struct {
    // Type is the type of namespace
    type: []u8,
    // Path is a path to an existing namespace persisted on disk that can be joined
    // and is of the same type
    path: ?[]u8 = null,
};

// LinuxDevice represents the mknod information for a Linux special device file
pub const LinuxDevice = struct {
    // Path to the device.
    path: []u8,
    // Device type, block, char, etc.
    type: []u8,
    // Major is the device's major number.
    major: u32,
    // Minor is the device's minor number.
    minor: u32,
    // FileMode permission bits for the device.
    fileMode: u32,
    // UID of the device.
    uid: u32 = 0,
    // Gid of the device.
    gid: u32 = 0,
};

test "parse runtime config generated by `crun spec`" {
    const options = std.json.ParseOptions{ .allocator = std.testing.allocator };
    const r = try std.json.parse(Spec, &std.json.TokenStream.init(@embedFile("runtime_spec.json")), options);
    defer std.json.parseFree(Spec, r, options);
}
