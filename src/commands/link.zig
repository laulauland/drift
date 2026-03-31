const std = @import("std");
const frontmatter = @import("../frontmatter.zig");
const scanner = @import("../scanner.zig");
const symbols = @import("../symbols.zig");
const vcs = @import("../vcs.zig");

pub fn run(
    allocator: std.mem.Allocator,
    stdout_w: *std.io.Writer,
    stderr_w: *std.io.Writer,
    spec_path: []const u8,
    optional_anchor: ?[]const u8,
) !void {
    const cwd_path = std.fs.cwd().realpathAlloc(allocator, ".") catch |err| {
        stderr_w.print("cannot resolve cwd: {s}\n", .{@errorName(err)}) catch {};
        return err;
    };
    defer allocator.free(cwd_path);

    const detected_vcs = vcs.detectVcs();
    const auto_change_id = vcs.getCurrentChangeId(allocator, cwd_path, detected_vcs) catch null;
    defer if (auto_change_id) |cid| allocator.free(cid);

    const cwd = std.fs.cwd();
    const content = cwd.readFileAlloc(allocator, spec_path, 1024 * 1024) catch |err| {
        stderr_w.print("cannot read {s}: {s}\n", .{ spec_path, @errorName(err) }) catch {};
        return err;
    };
    defer allocator.free(content);

    if (optional_anchor) |raw_anchor| {
        try linkTargeted(allocator, stdout_w, stderr_w, spec_path, raw_anchor, content, auto_change_id);
    } else {
        try linkBlanket(allocator, stdout_w, stderr_w, spec_path, content, auto_change_id);
    }
}

fn linkTargeted(
    allocator: std.mem.Allocator,
    stdout_w: *std.io.Writer,
    stderr_w: *std.io.Writer,
    spec_path: []const u8,
    raw_anchor: []const u8,
    content: []const u8,
    auto_change_id: ?[]const u8,
) !void {
    const anchor = blk: {
        const identity = frontmatter.anchorFileIdentity(raw_anchor);
        if (identity.len != raw_anchor.len) {
            break :blk raw_anchor;
        }
        const hash_pos = std.mem.indexOfScalar(u8, identity, '#');
        const target_file_path = if (hash_pos) |pos| identity[0..pos] else identity;
        const target_symbol = if (hash_pos) |pos| identity[pos + 1 ..] else null;

        if (symbols.computeContentSig(allocator, target_file_path, target_symbol)) |sig| {
            defer allocator.free(sig);
            break :blk std.fmt.allocPrint(allocator, "{s}@{s}", .{ raw_anchor, sig }) catch break :blk raw_anchor;
        }
        if (auto_change_id) |cid| {
            break :blk std.fmt.allocPrint(allocator, "{s}@{s}", .{ raw_anchor, cid }) catch break :blk raw_anchor;
        }
        break :blk raw_anchor;
    };
    const anchor_owned = anchor.ptr != raw_anchor.ptr;
    defer if (anchor_owned) allocator.free(anchor);

    const after_frontmatter = try frontmatter.linkAnchor(allocator, content, anchor);
    defer allocator.free(after_frontmatter);

    const target_file = frontmatter.anchorFileIdentity(raw_anchor);
    const target_hash_pos = std.mem.indexOfScalar(u8, target_file, '#');
    const target_path = if (target_hash_pos) |pos| target_file[0..pos] else target_file;

    const anchor_identity = frontmatter.anchorFileIdentity(anchor);
    const inline_provenance = if (anchor_identity.len < anchor.len) anchor[anchor_identity.len + 1 ..] else if (auto_change_id) |cid| cid else "unknown";
    const final_result = try scanner.updateInlineAnchors(allocator, after_frontmatter, target_path, inline_provenance);
    defer allocator.free(final_result);

    const file = std.fs.cwd().openFile(spec_path, .{ .mode = .write_only }) catch |err| {
        stderr_w.print("cannot write {s}: {s}\n", .{ spec_path, @errorName(err) }) catch {};
        return err;
    };
    defer file.close();

    try file.writeAll(final_result);
    try file.setEndPos(final_result.len);

    stdout_w.print("added {s} to {s}\n", .{ anchor, spec_path }) catch {};
}

fn linkBlanket(
    allocator: std.mem.Allocator,
    stdout_w: *std.io.Writer,
    stderr_w: *std.io.Writer,
    spec_path: []const u8,
    content: []const u8,
    auto_change_id: ?[]const u8,
) !void {
    const parsed_spec = frontmatter.parseDriftSpec(allocator, content);
    defer if (parsed_spec) |*ps| {
        var a = ps.anchors;
        for (a.items) |b| allocator.free(b);
        a.deinit(allocator);
        if (ps.origin) |o| allocator.free(o);
    };

    var intermediate: []const u8 = try allocator.dupe(u8, content);

    if (parsed_spec) |drift_spec| {
        for (drift_spec.anchors.items) |existing_anchor| {
            const identity = frontmatter.anchorFileIdentity(existing_anchor);
            const hash_pos = std.mem.indexOfScalar(u8, identity, '#');
            const anchor_file_path = if (hash_pos) |pos| identity[0..pos] else identity;
            const anchor_symbol = if (hash_pos) |pos| identity[pos + 1 ..] else null;

            const sig = symbols.computeContentSig(allocator, anchor_file_path, anchor_symbol);
            defer if (sig) |s| allocator.free(s);

            const provenance = sig orelse (auto_change_id orelse continue);
            const new_anchor = std.fmt.allocPrint(allocator, "{s}@{s}", .{ identity, provenance }) catch continue;
            defer allocator.free(new_anchor);

            const updated = frontmatter.linkAnchor(allocator, intermediate, new_anchor) catch continue;
            allocator.free(intermediate);
            intermediate = updated;
        }
    }

    const body_content = intermediate;
    var inline_anchors = scanner.parseInlineAnchors(allocator, body_content);
    defer {
        for (inline_anchors.items) |a| allocator.free(a);
        inline_anchors.deinit(allocator);
    }

    var after_inline: []const u8 = try allocator.dupe(u8, intermediate);
    allocator.free(intermediate);

    for (inline_anchors.items) |inline_anchor| {
        const inline_identity = frontmatter.anchorFileIdentity(inline_anchor);
        const inline_hash_pos = std.mem.indexOfScalar(u8, inline_identity, '#');
        const inline_file_path = if (inline_hash_pos) |pos| inline_identity[0..pos] else inline_identity;
        const inline_symbol = if (inline_hash_pos) |pos| inline_identity[pos + 1 ..] else null;

        const inline_sig = symbols.computeContentSig(allocator, inline_file_path, inline_symbol);
        defer if (inline_sig) |s| allocator.free(s);

        const inline_provenance = inline_sig orelse (auto_change_id orelse continue);
        const updated_inline = scanner.updateInlineAnchors(allocator, after_inline, inline_file_path, inline_provenance) catch continue;
        allocator.free(after_inline);
        after_inline = updated_inline;
    }

    const file = std.fs.cwd().openFile(spec_path, .{ .mode = .write_only }) catch |err| {
        stderr_w.print("cannot write {s}: {s}\n", .{ spec_path, @errorName(err) }) catch {};
        allocator.free(after_inline);
        return err;
    };
    defer file.close();

    try file.writeAll(after_inline);
    try file.setEndPos(after_inline.len);
    allocator.free(after_inline);

    stdout_w.print("relinked all anchors in {s}\n", .{spec_path}) catch {};
}
