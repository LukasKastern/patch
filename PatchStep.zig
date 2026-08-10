const std = @import("std");
const fs = std.fs;
const LazyPath = std.Build.LazyPath;
const PatchStep = @This();

pub const Options = struct {
    root_directory: LazyPath,
    patch_dep_name: []const u8 = "patch",
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: u32 = 0,
    patches: []const std.Build.LazyPath,
};

pub fn patch(b: *std.Build, options: Options) std.Build.LazyPath {
    const patch_dep = b.dependency(options.patch_dep_name, .{
        .target = options.target,
        .optimize = options.optimize,
    });

    // Grab runner
    const runner = patch_dep.artifact("patch_runner");

    // Create run artifact
    var execute_runner = b.addRunArtifact(runner);

    // Patch executable
    execute_runner.addFileArg(patch_dep.artifact("patch").getEmittedBin());

    // Directory we are going to patch
    execute_runner.addDirectoryArg2(options.root_directory, .{});

    // Output of the patching process
    const output = execute_runner.addOutputDirectoryArg2(options.patch_dep_name, .{});

    // Strip arg
    execute_runner.addArg(b.fmt("{d}", .{options.strip}));

    // Add patches are input arguments
    for (options.patches) |p| {
        execute_runner.addFileArg(p);
    }

    execute_runner.addCheck(.{ .expect_term = .{ .exited = 0 } });

    // Return the result of executing the patch runner
    return output;
}
