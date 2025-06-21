const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target: Build.ResolvedTarget = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});

    const iter_module: *Build.Module = b.addModule("iter_z", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/iter.zig"),
    });

    {
        const iter_test: *Build.Step.Compile = b.addTest(.{
            .root_source_file = b.path("test/iter_tests.zig"),
            .target = target,
            .optimize = optimize,
            .error_tracing = true,
        });
        iter_test.root_module.addImport("iter_z", iter_module);

        const run_test: *Build.Step.Run = b.addRunArtifact(iter_test);
        run_test.has_side_effects = true;

        const test_step: *Build.Step = b.step("test", "Run iterator unit tests");
        test_step.dependOn(&run_test.step);
    }
}
