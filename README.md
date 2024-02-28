# zlog

Simple structured logging for Zig.

## Usage

Add the following dependency to your `build.zig.zon` file's dependencies section:

```
.zlog = .{
    .url = "https://github.com/jcalabro/zlog/archive/main.tar.gz",
    .hash = "<hash>",
}
```

Add the following to your `build.zig`:

```zig
const zlog_dep = b.dependency("zlog", .{});
const zlog_mod = zlog_dep.module("zlog");
exe.root_module.addImport("zlog", zlog_mod);
```

Once at startup in your program, call `init`:

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    try zlog.init(.{
        .allocator = std.heap.c_allocator,
        .level = .dbg,
        .regions = "all",
        .fp = std.io.getStdOut(),
    });
    defer zlog.deinit();

    // your code here...
}
```

Then, you can use the logger throughout your program like so:

```zig
const log = logger.Logger.init("myregion");

fn foo() void {
    // formatted and unformatted log functions for each level are available
    log.debugf("hello {s}", .{"world"});
    log.info("hello world");
    log.warn("hello world");
    log.err("hello world");
    log.fatal("hello world"); // exits the program
}
```
