const std = @import("std");
const frontmatter = @import("../frontmatter.zig");

pub fn run(
    allocator: std.mem.Allocator,
    stdout_w: *std.io.Writer,
    stderr_w: *std.io.Writer,
    spec_path: []const u8,
    anchor: []const u8,
) !void {
    const cwd = std.fs.cwd();
    const content = cwd.readFileAlloc(allocator, spec_path, 1024 * 1024) catch |err| {
        stderr_w.print("cannot read {s}: {s}\n", .{ spec_path, @errorName(err) }) catch {};
        return err;
    };
    defer allocator.free(content);

    const result = try frontmatter.unlinkAnchor(allocator, content, anchor);
    defer allocator.free(result.content);

    if (result.removed) {
        const file = cwd.openFile(spec_path, .{ .mode = .write_only }) catch |err| {
            stderr_w.print("cannot write {s}: {s}\n", .{ spec_path, @errorName(err) }) catch {};
            return err;
        };
        defer file.close();

        try file.writeAll(result.content);
        try file.setEndPos(result.content.len);

        stdout_w.print("removed {s} from {s}\n", .{ anchor, spec_path }) catch {};
    }
}
