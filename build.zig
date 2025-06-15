const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target: Build.ResolvedTarget = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});

    const iter_module: *Build.Module = b.addModule("iter_z", .{
        .root_source_file = b.path("src/iter.zig"),
    });

    const benchmarking_module: *Build.Module = b.addModule("benchmarking", .{
        .root_source_file = b.path("src/benchmarking/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // using https://github.com/karlseguin/zul for benchmarking (not a dependency of the library tho)
    const zul_module: *Build.Module = b.dependency("zul", .{}).module("zul");
    benchmarking_module.addImport("zul", zul_module);
    benchmarking_module.addImport("iter_z", iter_module);

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

    const benchmark_exe: *Build.Step.Compile = b.addExecutable(Build.ExecutableOptions{
        .name = "benchmarks",
        .root_module = benchmarking_module,
    });

    b.installArtifact(benchmark_exe);
    const run_benchmarks: *Build.Step.Run = b.addRunArtifact(benchmark_exe);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build benchmarks`
    // This will evaluate the `benchmarks` step rather than the default, which is "install".
    const run_benchmarks_step: *Build.Step = b.step("benchmarks", "Run the benchmarks");
    run_benchmarks_step.dependOn(&run_benchmarks.step);
}
