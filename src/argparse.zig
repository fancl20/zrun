const std = @import("std");

pub const ArgParseOptions = struct {
    allocator: *std.mem.Allocator = std.heap.c_allocator,
};

const ArgParseError = error{
    AllocatorRequired,
    InvalidArgs,
    MissingField,
    UnexpectedArgument,
    UnexpectedField,
};

pub fn parse(comptime T: type, options: ArgParseOptions) !T {
    var args = std.ArrayList([]const u8).init(options.allocator);
    defer args.deinit();
    for (std.os.argv) |arg| {
        var str = std.mem.spanZ(arg);
        if (std.mem.startsWith(u8, str, "--")) {
            if (std.mem.indexOf(u8, str, "=")) |idx| {
                try args.append(str[0..idx]);
                str = str[idx + 1 ..];
            }
        }
        try args.append(str);
    }
    return parseInternal(T, args.items[1..], options);
}

fn parseInternal(comptime T: type, args: []const []const u8, options: ArgParseOptions) ArgParseError!T {
    const info = @typeInfo(T).Struct;
    var result: T = undefined;

    var fields_seen = [_]bool{false} ** info.fields.len;

    var iter = try splitArgs(args);
    while (iter.next()) |kv| {
        const key = kv[0][2..]; // Remove -- prefix
        const val = kv[1..];
        var found = false;
        inline for (info.fields) |field, field_i| {
            if (std.mem.eql(u8, key, field.name)) {
                fields_seen[field_i] = true;
                @field(result, field.name) = try parseValues(field.field_type, val, options);
                found = true;
                break;
            }
        }
        if (!found) {
            return error.UnexpectedField;
        }
    }

    // Set default value
    inline for (info.fields) |field, i| {
        if (!fields_seen[i]) {
            if (field.default_value) |default| {
                if (!field.is_comptime) {
                    @field(result, field.name) = default;
                }
            } else {
                return error.MissingField;
            }
        }
    }

    return result;
}

fn splitArgs(args: []const []const u8) ArgParseError!SplitIterator {
    if (args.len == 0) {
        return SplitIterator{ .args = args, .index = null };
    }
    if (!std.mem.startsWith(u8, args[0], "--")) {
        return error.InvalidArgs;
    }
    return SplitIterator{
        .args = args,
        .index = 0,
    };
}

const SplitIterator = struct {
    args: []const []const u8,
    index: ?usize,

    pub fn next(self: *SplitIterator) ?[]const []const u8 {
        const start = self.index orelse return null;
        const end = if (indexOfPos(self.args, start + 1)) |key_start| blk: {
            self.index = key_start;
            break :blk key_start;
        } else blk: {
            self.index = null;
            break :blk self.args.len;
        };
        return self.args[start..end];
    }

    /// Returns a slice of the remaining bytes. Does not affect iterator state.
    pub fn rest(self: SplitIterator) []const []const u8 {
        const end = self.args.len;
        const start = self.index orelse end;
        return self.args[start..end];
    }

    fn indexOfPos(args: []const []const u8, start_index: usize) ?usize {
        var i: usize = start_index;
        while (i < args.len) : (i += 1) {
            if (std.mem.startsWith(u8, args[i], "--")) {
                return i;
            }
        }
        return null;
    }
};

fn parseValues(comptime T: type, values: []const []const u8, options: ArgParseOptions) ArgParseError!T {
    if (values.len != 1) {
        return error.InvalidArgs;
    }
    switch (@typeInfo(T)) {
        .Bool => {
            if (std.mem.eql(u8, values[0], "true")) return true;
            if (std.mem.eql(u8, values[0], "false")) return false;
            return error.InvalidArgs;
        },
        .Float, .ComptimeFloat => {
            return try std.fmt.parseFloat(T, values[0]) catch error.InvalidArgs;
        },
        .Int, .ComptimeInt => {
            return std.fmt.parseInt(T, values[0], 10) catch error.InvalidArgs;
        },
        .Optional => |optionalInfo| {
            return try parseValues(optionalInfo.child, values, options);
        },
        .Pointer => |ptrInfo| {
            switch (ptrInfo.size) {
                .One => {
                    const allocator = options.allocator orelse return error.AllocatorRequired;
                    const r: T = try allocator.create(ptrInfo.child);
                    r.* = try parseValues(ptrInfo.child, values, options);
                    return r;
                },
                .Slice => {
                    if (ptrInfo.child != u8) return error.InvalidArgs;
                    return values[0];
                },
                else => return error.InvalidArgs,
            }
        },
        else => return error.InvalidArgs,
    }
}

pub fn parseFree(comptime T: type, value: T, options: ArgParseOptions) void {
    inline for (@typeInfo(T).Struct.fields) |field| {
        fieldFree(field.field_type, @field(value, field.name), options);
    }
}

fn fieldFree(comptime T: type, value: T, options: ArgParseOptions) void {
    switch (@typeInfo(T)) {
        .Bool, .Float, .ComptimeFloat, .Int, .ComptimeInt => {},
        .Optional => |optionalInfo| {
            if (value) |v| {
                fieldFree(optionalInfo.child, v, options);
            }
        },
        .Pointer => |ptrInfo| {
            switch (ptrInfo.size) {
                .One => {
                    fieldFree(ptrInfo.child, value.*, options);
                    options.allocator.destroy(value);
                },
                .Slice => {
                    for (value) |v| {
                        fieldFree(ptrInfo.child, v, options);
                    }
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "parse multiple fields" {
    const Args = struct {
        str: []const u8,
        boolean: bool,
        default: []const u8 = "default",
        float: f64,
        int: u32,
        optional_str: ?[]const u8 = null,
    };
    const options = ArgParseOptions{ .allocator = std.testing.allocator };
    const parsed = try parseInternal(Args, &[_][]const u8{
        "--str",
        "test",
        "--boolean",
        "false",
        "--float",
        "1.1",
        "--int",
        "1234",
        "--optional_str",
        "optional",
    }, options);
    try std.testing.expectEqual(@as([]const u8, "test"), parsed.str);
    try std.testing.expectEqual(false, parsed.boolean);
    try std.testing.expectEqual(@as(f64, 1.1), parsed.float);
    try std.testing.expectEqual(@as(u32, 1234), parsed.int);
    try std.testing.expectEqual(@as(?[]const u8, "optional"), parsed.optional_str);
    defer parseFree(Args, parsed, options);
}

test "parse default values" {
    const Args = struct {
        str: []const u8 = "test",
        boolean: bool = false,
        float: f64 = 1.1,
        int: u32 = 1234,
        optional: ?u32 = null,
    };
    const options = ArgParseOptions{ .allocator = std.testing.allocator };
    const parsed = try parseInternal(Args, &[_][]const u8{}, options);
    try std.testing.expectEqual(@as([]const u8, "test"), parsed.str);
    try std.testing.expectEqual(false, parsed.boolean);
    try std.testing.expectEqual(@as(f64, 1.1), parsed.float);
    try std.testing.expectEqual(@as(u32, 1234), parsed.int);
    try std.testing.expectEqual(@as(?u32, null), parsed.optional);
    defer parseFree(Args, parsed, options);
}

test "parse missing field" {
    const Args = struct {
        str: []const u8,
    };
    const options = ArgParseOptions{ .allocator = std.testing.allocator };
    const parsed = parseInternal(Args, &[_][]const u8{}, options);
    try std.testing.expectError(error.MissingField, parsed);
}

test "parse unexpected field" {
    const Args = struct {
        str: []const u8,
    };
    const options = ArgParseOptions{ .allocator = std.testing.allocator };
    const parsed = parseInternal(Args, &[_][]const u8{
        "--str",
        "test",
        "--something",
        "some",
    }, options);
    try std.testing.expectError(error.UnexpectedField, parsed);
}
