# zlog

Simple structured logging for Zig.

## Usage

Once at startup in your program, call `init`:

```zig
const std = @import("std");
const fs = std.fs;
const zlog = @import("zlog");

pub fn main() !void {
    // open a file and seek to the end
    const path = "/tmp/myfile.txt";
    var fp: ?fs.File = null;
    if (fs.openFileAbsolute(path, fs.File.OpenFlags{ .mode = .read_write })) |f| {
        // the file exists, read until the end to we don't overwrite its contents
        const stat = try f.stat();
        try f.seekTo(stat.size);
        fp = f;
    } else |err| {
        switch (err) {
            error.FileNotFound => {
                // the file does not exist, so create it
                fp = try fs.createFileAbsolute(opts.file_path, fs.File.CreateFlags{});
            },
            else => return err,
        }
    }
    std.debug.assert(fp != null);

    try zlog.init(.{
        .allocator = std.heap.c_allocator,
        .level = .wrn,
        .regions = "all",
        .writer = fp.writer(),
        .color = false,
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
