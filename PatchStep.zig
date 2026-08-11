const std = @import("std");
const fs = std.fs;
const LazyPath = std.Build.LazyPath;

pub const Options = struct {
    // Directory to patch
    root_directory: LazyPath,

    patch_dep_name: []const u8 = "patch",
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: u32 = 0,

    // Patches to apply to the root directory
    patches: []const std.Build.LazyPath,
};

// Configure a run artifacts that executes the patches in the given options
// Returns the path to the patched output directory
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
    execute_runner.addDirectoryArg(options.root_directory);

    // Output of the patching process
    const output = execute_runner.addOutputDirectoryArg(options.patch_dep_name);

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
