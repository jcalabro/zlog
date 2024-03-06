const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const Mutex = std.Thread.Mutex;
const testing = std.testing;

const time = @import("time");

pub const Level = enum {
    ftl,
    err,
    wrn,
    inf,
    dbg,

    pub fn num(self: @This()) u8 {
        return switch (self) {
            .ftl => 5,
            .err => 4,
            .wrn => 3,
            .inf => 2,
            .dbg => 1,
        };
    }
};

pub const Options = struct {
    allocator: Allocator,

    level: Level = Level.dbg,

    regions: []const u8 = "all",
    active_regions: [][]const u8 = undefined,

    fp: fs.File,

    color: bool = true,

    // only one thread is allowed to write to the output file at a time
    mu: Mutex = Mutex{},

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.active_regions);
    }
};

// opts must be set at startup via one call to init(), then never modifided later
var opts: Options = undefined;

pub fn init(op: Options) !void {
    opts = op;

    opts.active_regions = blk: {
        var activeRegions = std.ArrayList([]const u8).init(opts.allocator);
        errdefer activeRegions.deinit();

        // split up regions based on "," and trim remaining whitespace
        const whitespace = " \r\t\x00";
        var iter = mem.split(u8, opts.regions, ",");
        try activeRegions.append(iter.first());
        var next = iter.next();
        while (next != null) {
            const region = mem.trim(u8, next.?, whitespace);
            try activeRegions.append(region);
            next = iter.next();
        }

        break :blk try activeRegions.toOwnedSlice();
    };
}

pub fn deinit() void {
    opts.deinit();
}

const Color = enum {
    Red,
    Green,
    Yellow,
    Blue,
    Reset,

    fn str(self: Color) []const u8 {
        return switch (self) {
            .Red => "\x1b[31m",
            .Green => "\x1b[32m",
            .Yellow => "\x1b[33m",
            .Blue => "\x1b[34m",
            .Reset => "\x1b[0m",
        };
    }
};

pub const Logger = struct {
    const Self = @This();

    region: []const u8,

    pub fn init(comptime region: []const u8) Self {
        return Self{
            .region = region,
        };
    }

    fn write(self: Self, comptime fmt: []const u8, args: anytype, lvl: Level, color: Color) void {
        const globalLvl = opts.level.num();
        const localLvl = lvl.num();
        if (localLvl < globalLvl) {
            // log level is not high enough
            return;
        }

        var ok = false;
        for (opts.active_regions) |region| {
            if (mem.eql(u8, region, "all") or mem.eql(u8, region, self.region)) {
                ok = true;
                break;
            }
        }
        if (!ok) {
            // region is not enabled
            return;
        }

        const colorStr = switch (opts.color) {
            true => color.str(),
            false => Color.Reset.str(),
        };

        // @PERFORMANCE (jrc): can we get a small improvement by only calling allocPrint once below?
        const msg = std.fmt.allocPrint(opts.allocator, fmt, args) catch return;
        defer opts.allocator.free(msg);

        // RFC 3999 (i.e. 2023-01-19T08:37:01, in UTC since that's all that time.zig supports)
        const timeFmt = "YYYY-MM-DDTHH:mm:ss";
        var now = [_]u8{0} ** timeFmt.len;
        var buf = io.fixedBufferStream(&now);
        time.DateTime.now().format(timeFmt, .{}, buf.writer()) catch return;

        // [level] [region] [time] message
        const output = std.fmt.allocPrint(opts.allocator, "{s}[{s}] [{s}] [{s}]{s} {s}\n", .{
            .color = colorStr,
            .level = @tagName(lvl),
            .region = self.region,
            .now = now,
            .reset = Color.Reset.str(), // reset to the default terminal color
            .msg = msg,
        }) catch return;
        defer opts.allocator.free(output);

        opts.mu.lock();
        defer opts.mu.unlock();

        opts.fp.writeAll(output) catch return;
    }

    pub fn debug(self: @This(), comptime fmt: []const u8) void {
        debugf(self, fmt, .{});
    }

    pub fn debugf(self: @This(), comptime fmt: []const u8, args: anytype) void {
        write(self, fmt, args, Level.dbg, Color.Green);
    }

    pub fn info(self: @This(), comptime fmt: []const u8) void {
        infof(self, fmt, .{});
    }

    pub fn infof(self: @This(), comptime fmt: []const u8, args: anytype) void {
        write(self, fmt, args, Level.inf, Color.Blue);
    }

    pub fn warn(self: @This(), comptime fmt: []const u8) void {
        warnf(self, fmt, .{});
    }

    pub fn warnf(self: @This(), comptime fmt: []const u8, args: anytype) void {
        write(self, fmt, args, Level.wrn, Color.Yellow);
    }

    pub fn err(self: @This(), comptime fmt: []const u8) void {
        errf(self, fmt, .{});
    }

    pub fn errf(self: @This(), comptime fmt: []const u8, args: anytype) void {
        write(self, fmt, args, Level.err, Color.Red);
    }

    pub fn fatal(self: @This(), comptime fmt: []const u8) void {
        fatalf(self, fmt, .{});
    }

    pub fn fatalf(self: @This(), comptime fmt: []const u8, args: anytype) void {
        write(self, fmt, args, Level.ftl, Color.Red);
        std.os.exit(1);
    }
};

test "logging" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const fp = try tmp_dir.dir.createFile("log.txt", .{
        .read = true,
    });
    defer fp.close();

    {
        //
        // Write some data
        //

        try init(.{
            .allocator = testing.allocator,
            .level = .wrn,
            .regions = "all",
            .fp = fp,
            .color = false,
        });
        defer deinit();

        const log = Logger.init("myregion");

        log.debug("hello");
        log.info("world");
        log.warnf("testing {d}", .{123});
        log.err("final");
    }

    {
        //
        // Read the data and ensure it contains what we expect
        //

        try fp.sync();
        try fp.seekTo(0);

        const contents = try testing.allocator.alloc(u8, 2048);
        defer testing.allocator.free(contents);
        @memset(contents, 0);

        const num_bytes = try fp.readAll(contents);
        try testing.expect(num_bytes > 0);

        var ndx: usize = 0;
        var it = mem.splitSequence(u8, contents, "\n");
        while (it.next()) |line| : (ndx += 1) {
            const header_bytes = 47;
            const trimmed = line[header_bytes..];
            if (trimmed.len == 0 or trimmed[0] == '\x00') continue;

            try switch (ndx) {
                0 => testing.expectEqualSlices(u8, "testing 123", trimmed),
                1 => testing.expectEqualSlices(u8, "final", trimmed),
                else => unreachable,
            };
        }
    }
}
