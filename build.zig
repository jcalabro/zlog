const std = @import("std");

pub fn build(b: *std.Build) void {
    const zlog = b.addModule("zlog", .{
        .root_source_file = .{ .path = "src/zlog.zig" },
    });

    const time_dep = b.dependency("time", .{});
    const time_mod = time_dep.module("time");
    zlog.addImport("time", time_mod);

    {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});

        const tests = b.addTest(.{
            .root_source_file = .{ .path = "src/zlog.zig" },
            .target = target,
            .optimize = optimize,
        });

        tests.root_module.addImport("zlog", zlog);
        tests.root_module.addImport("time", time_mod);

        const run_tests = b.addRunArtifact(tests);
        const tests_step = b.step("test", "Run all the tests.");
        tests_step.dependOn(&run_tests.step);
    }
}
