# zrun

A fast and low-memory footprint container runtime fully written in Zig.

zrun is similar to crun and runc, although not targeting implementing full OCI standard. It trying to implement minimal feature set to make container just works.

It's only designed for running trusty image. If you find your image broken in zrun, please file a issue.

## Usage

Please check example runtime_spec.json.

Use command line args like `zrun --bundle=/path/to/bundle` to override the default config.

```zig
struct {
    bundle: []const u8 = ".",
    config: []const u8 = "runtime_spec.json",
    detach: bool = false,
    // TODO: implement pid_file
    pid_file: ?[]const u8 = null,
};
```

## Roadmap

### Goal

- Only support minimum feature and latest kernel, which removes a lot of complexities.
- Make best effort to comply with a subset of the OCI spec.

### Non Goal

- Isolation & Security: It's only designed for running trusty image. And removing the support of cgroups and capability control can eliminates most part of code.
