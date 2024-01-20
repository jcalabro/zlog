# zlog

Simple structured logging for Zig.

## Usage

Once at startup in your program, call `init`:

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    try zlog.init(.{
        .allocator = std.heap.c_allocator,
        .level = .dbg,
        .regions = "all",
        .writer = std.io.getStdOut(),
    });
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
