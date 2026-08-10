const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var arg_it = try init.minimal.args.iterateAllocator(init.gpa);

    // Skip process
    _ = arg_it.next();

    // Grab input args
    // Needs to be kept in sync with patch_step
    const patch_path = arg_it.next() orelse return error.InvalidInput;
    const to_patch_patch = arg_it.next() orelse return error.InvalidInput;
    const output_dir_path = arg_it.next() orelse return error.InvalidInput;
    const strip = arg_it.next() orelse return error.InvalidInput;

    // Copy from input dir to output
    var cwd = std.Io.Dir.cwd();

    // Open output dir
    var output_dir = cwd.openDir(init.io, output_dir_path, .{ .access_sub_paths = true }) catch |e| {
        std.log.err("output dir {s} not found", .{output_dir_path});
        return e;
    };
    defer output_dir.close(init.io);

    // Copy from to patch to output
    {
        // Open the directory we want to patch
        var to_patch_dir = cwd.openDir(init.io, to_patch_patch, .{
            .access_sub_paths = true,
            .follow_symlinks = false,
            .iterate = true,
        }) catch |e| {
            std.log.err("to patch dir not found {}", .{e});
            return e;
        };
        defer to_patch_dir.close(init.io);

        var to_patch_it = try to_patch_dir.walkSelectively(init.gpa);
        defer to_patch_it.deinit();

        while (try to_patch_it.next(init.io)) |entry| {
            switch (entry.kind) {
                .directory => {
                    output_dir.createDirPath(init.io, entry.path) catch |e| {
                        std.log.err("createDirPath {s} failed {}", .{ entry.path, e });
                        return e;
                    };

                    try to_patch_it.enter(init.io, entry);
                },
                .file => {
                    to_patch_dir.copyFile(entry.path, output_dir, entry.path, init.io, .{ .make_path = true }) catch |e| {
                        std.log.err("copyFile {s} failed {}", .{ entry.path, e });
                        return e;
                    };
                },
                else => continue,
            }
        }
    }

    // Apply patches over the output directory
    while (arg_it.next()) |patch_file| {
        var argv_list: std.ArrayList([]const u8) = .empty;
        defer argv_list.deinit(init.arena.allocator());

        try argv_list.append(init.arena.allocator(), patch_path);

        try argv_list.append(init.arena.allocator(), "--strip");
        try argv_list.append(init.arena.allocator(), strip);

        try argv_list.append(init.arena.allocator(), "--quiet");
        try argv_list.append(init.arena.allocator(), "--no-backup-if-mismatch");

        try argv_list.append(init.arena.allocator(), "--directory");
        try argv_list.append(init.arena.allocator(), output_dir_path);

        try argv_list.append(init.arena.allocator(), "--input");
        const patch_file_path = try cwd.realPathFileAlloc(init.io, patch_file, init.arena.allocator());
        try argv_list.append(init.arena.allocator(), patch_file_path);

        var child = std.process.spawn(init.io, .{
            .argv = argv_list.items,
            .cwd = .inherit,
            .stdin = .ignore,
            .stdout = .inherit,
            .stderr = .inherit,
        }) catch |err| {
            std.log.err("unable to spawn patch process {s}: {}", .{ patch_path, err });
            return err;
        };
        const res = child.wait(init.io) catch |err| {
            std.log.err("patch process failed {}", .{err});
            return err;
        };
        if (res != .exited or res.exited != 0) {
            std.log.err("patch failed {any}", .{res});
            return error.PatchFailed;
        }
    }
}
