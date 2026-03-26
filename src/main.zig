const std = @import("std");
const build_options = @import("build_options");
const clap = @import("clap");
const frontmatter = @import("frontmatter.zig");
const scanner = @import("scanner.zig");
const symbols = @import("symbols.zig");
const vcs = @import("vcs.zig");

const Spec = scanner.Spec;

const version = build_options.version;

const SubCommand = enum {
    check,
    lint,
    status,
    link,
    unlink,
    help,
};

const main_params = clap.parseParamsComptime(
    \\-h, --help    Show this help message.
    \\-V, --version Show version.
    \\<command>
    \\
);

const main_parsers = .{
    .command = clap.parsers.string,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_w = std.fs.File.stdout().writer(&stdout_buf);
    var stderr_w = std.fs.File.stderr().writer(&stderr_buf);
    defer stdout_w.interface.flush() catch {};
    defer stderr_w.interface.flush() catch {};

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &main_params, main_parsers, .{
        .diagnostic = &diag,
        .allocator = allocator,
        .terminating_positional = 0,
    }) catch |err| {
        diag.report(&stderr_w.interface, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        printUsage(&stdout_w.interface);
        return;
    }

    if (res.args.version != 0) {
        stdout_w.interface.print("drift {s}\n", .{version}) catch return error.WriteFailed;
        return;
    }

    const command_str = res.positionals[0] orelse {
        printUsage(&stdout_w.interface);
        return;
    };

    const command = std.meta.stringToEnum(SubCommand, command_str) orelse {
        stderr_w.interface.print("unknown command: {s}\n", .{command_str}) catch {};
        stderr_w.interface.print("available commands: check, lint, status, link, unlink\n", .{}) catch {};
        return error.InvalidCommand;
    };

    switch (command) {
        .check, .lint => runLint(allocator, &stdout_w.interface, &stderr_w.interface) catch |err| {
            exitWithCommandError(&stderr_w.interface, "lint", err);
        },
        .status => runStatus(allocator, &stdout_w.interface, &stderr_w.interface) catch |err| {
            exitWithCommandError(&stderr_w.interface, "status", err);
        },
        .link => runLink(allocator, &stdout_w.interface, &stderr_w.interface) catch |err| {
            exitWithCommandError(&stderr_w.interface, "link", err);
        },
        .unlink => runUnlink(allocator, &stdout_w.interface, &stderr_w.interface) catch |err| {
            exitWithCommandError(&stderr_w.interface, "unlink", err);
        },
        .help => printUsage(&stdout_w.interface),
    }
}

fn printUsage(w: *std.io.Writer) void {
    w.print(
        \\drift — bind specs to code, lint for drift
        \\
        \\Usage: drift <command> [options]
        \\
        \\Commands:
        \\  lint      Check all specs for staleness
        \\  status    Show all specs and their anchors
        \\  link      Add anchors to a spec
        \\  unlink    Remove anchors from a spec
        \\
        \\Options:
        \\  -h, --help     Show this help message
        \\  -V, --version  Show version
        \\
    , .{}) catch {};
}

fn exitWithCommandError(stderr_w: *std.io.Writer, command: []const u8, err: anyerror) noreturn {
    stderr_w.print("{s} error: {s}\n", .{ command, @errorName(err) }) catch {};
    stderr_w.flush() catch {};
    std.process.exit(1);
}

fn loadSpecsWithInlineAnchors(allocator: std.mem.Allocator, specs: *std.ArrayList(Spec)) !void {
    try scanner.findSpecs(allocator, specs);

    for (specs.items) |*spec| {
        const content = try std.fs.cwd().readFileAlloc(allocator, spec.path, 1024 * 1024);
        defer allocator.free(content);

        var inline_anchors = scanner.parseInlineAnchors(allocator, content);
        defer inline_anchors.deinit(allocator);

        for (inline_anchors.items) |anchor| {
            var already_bound = false;
            for (spec.anchors.items) |existing| {
                if (std.mem.eql(u8, existing, anchor)) {
                    already_bound = true;
                    break;
                }
            }

            if (already_bound) {
                allocator.free(anchor);
                continue;
            }

            spec.anchors.append(allocator, anchor) catch |err| {
                allocator.free(anchor);
                return err;
            };
        }
    }

    std.mem.sort(Spec, specs.items, {}, struct {
        fn lessThan(_: void, a: Spec, b: Spec) bool {
            return std.mem.order(u8, a.path, b.path) == .lt;
        }
    }.lessThan);
}

fn runLint(allocator: std.mem.Allocator, stdout_w: *std.io.Writer, stderr_w: *std.io.Writer) !void {
    var specs: std.ArrayList(Spec) = .{};
    defer {
        for (specs.items) |*s| s.deinit(allocator);
        specs.deinit(allocator);
    }

    try loadSpecsWithInlineAnchors(allocator, &specs);

    // Get absolute cwd for VCS commands
    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);

    const detected_vcs = vcs.detectVcs();
    var has_issues = false;

    for (specs.items) |spec| {
        stdout_w.print("{s}\n", .{spec.path}) catch {};

        if (spec.anchors.items.len == 0) {
            stdout_w.print("  ok\n", .{}) catch {};
            continue;
        }

        // Get last commit/change that touched the spec file
        const spec_commit = vcs.getLastCommit(allocator, cwd_path, spec.path, detected_vcs) catch |err| {
            stderr_w.print("vcs error for {s}: {s}\n", .{ spec.path, @errorName(err) }) catch {};
            return error.LintCheckFailed;
        };
        defer if (spec_commit) |c| allocator.free(c);

        var all_ok = true;

        for (spec.anchors.items) |anchor| {
            const status = checkAnchor(allocator, cwd_path, anchor, spec_commit, detected_vcs) catch |err| {
                stderr_w.print("error checking {s}: {s}\n", .{ anchor, @errorName(err) }) catch {};
                return error.LintCheckFailed;
            };
            defer status.deinit(allocator);

            if (!std.mem.eql(u8, status.label, "ok")) {
                has_issues = true;
                all_ok = false;
                if (status.reason.len > 0) {
                    stdout_w.print("  {s}   {s} ({s})\n", .{ status.label, status.display, status.reason }) catch {};
                } else {
                    stdout_w.print("  {s}   {s}\n", .{ status.label, status.display }) catch {};
                }
                if (status.blame) |blame| {
                    stdout_w.print("          changed by {s} in {s} ({s})\n", .{ blame.author, blame.commit_hash, blame.date }) catch {};
                    stdout_w.print("          \"{s}\"\n", .{blame.subject}) catch {};
                }
            }
        }

        if (all_ok) {
            stdout_w.print("  ok\n", .{}) catch {};
        }
    }

    if (specs.items.len == 0) {
        stdout_w.print("ok\n", .{}) catch {};
    }

    if (has_issues) {
        stdout_w.flush() catch {};
        stderr_w.flush() catch {};
        std.process.exit(1);
    }
}

const AnchorStatus = struct {
    label: []const u8,
    display: []const u8,
    reason: []const u8,
    blame: ?vcs.BlameInfo = null,

    fn deinit(self: AnchorStatus, allocator: std.mem.Allocator) void {
        allocator.free(self.label);
        allocator.free(self.reason);
        if (self.blame) |blame| blame.deinit(allocator);
    }
};

fn checkAnchor(
    allocator: std.mem.Allocator,
    cwd_path: []const u8,
    anchor: []const u8,
    spec_commit: ?[]const u8,
    detected_vcs: vcs.VcsKind,
) !AnchorStatus {
    // Parse the anchor: extract file_path, symbol_name (optional), provenance (optional)
    const identity = frontmatter.anchorFileIdentity(anchor);
    const provenance: ?[]const u8 = if (identity.len < anchor.len)
        anchor[identity.len + 1 ..]
    else
        null;

    // Split identity on # to get file_path and symbol_name
    const hash_pos = std.mem.indexOfScalar(u8, identity, '#');
    const file_path = if (hash_pos) |pos| identity[0..pos] else identity;
    const symbol_name = if (hash_pos) |pos| identity[pos + 1 ..] else null;

    // Check if the file exists
    const file_exists = blk: {
        std.fs.cwd().access(file_path, .{}) catch break :blk false;
        break :blk true;
    };

    if (!file_exists) {
        return .{
            .label = try allocator.dupe(u8, "STALE"),
            .display = anchor,
            .reason = try allocator.dupe(u8, "file not found"),
        };
    }

    // If symbol anchor, check if symbol exists in the file via tree-sitter
    if (symbol_name) |sym| {
        const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch {
            return .{
                .label = try allocator.dupe(u8, "STALE"),
                .display = anchor,
                .reason = try allocator.dupe(u8, "file not readable"),
            };
        };
        defer allocator.free(file_content);

        const ext = std.fs.path.extension(file_path);
        if (symbols.languageForExtension(ext)) |lang_query| {
            if (!symbols.resolveSymbolWithTreeSitter(file_content, lang_query, sym)) {
                return .{
                    .label = try allocator.dupe(u8, "STALE"),
                    .display = anchor,
                    .reason = try allocator.dupe(u8, "symbol not found"),
                };
            }
        } else {
            // Fallback to string search for unsupported languages
            if (std.mem.indexOf(u8, file_content, sym) == null) {
                return .{
                    .label = try allocator.dupe(u8, "STALE"),
                    .display = anchor,
                    .reason = try allocator.dupe(u8, "symbol not found"),
                };
            }
        }
    }

    // Compare current state against the anchor's baseline revision.
    // If the anchor has explicit provenance, use that. Otherwise fall back to
    // the last revision that touched the spec file.
    if (provenance) |prov| {
        return checkAnchorByContent(allocator, cwd_path, anchor, file_path, symbol_name, prov, spec_commit, detected_vcs);
    }
    if (spec_commit) |commit| {
        return checkAnchorByContent(allocator, cwd_path, anchor, file_path, symbol_name, commit, spec_commit, detected_vcs);
    }

    return .{
        .label = try allocator.dupe(u8, "ok"),
        .display = anchor,
        .reason = try allocator.dupe(u8, ""),
    };
}

fn checkAnchorByContent(
    allocator: std.mem.Allocator,
    cwd_path: []const u8,
    anchor: []const u8,
    file_path: []const u8,
    symbol_name: ?[]const u8,
    provenance: []const u8,
    spec_commit: ?[]const u8,
    detected_vcs: vcs.VcsKind,
) !AnchorStatus {
    // Get historical content at provenance revision.
    // Fall back to spec's last commit if provenance is unresolvable (e.g. manually-written jj change ID).
    const historical_content = blk: {
        const from_prov = vcs.getFileAtRevision(allocator, cwd_path, provenance, file_path, detected_vcs) catch null;
        if (from_prov) |content| break :blk content;
        if (spec_commit) |sc| {
            break :blk vcs.getFileAtRevision(allocator, cwd_path, sc, file_path, detected_vcs) catch null;
        }
        break :blk null;
    };
    defer if (historical_content) |hc| allocator.free(hc);

    // Read current file from disk
    const current_content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch {
        return .{
            .label = try allocator.dupe(u8, "STALE"),
            .display = anchor,
            .reason = try allocator.dupe(u8, "file not found"),
        };
    };
    defer allocator.free(current_content);

    if (historical_content == null) {
        return staleChangedAfterSpec(allocator, cwd_path, anchor, file_path, provenance, detected_vcs);
    }

    if (symbol_name) |sym| {
        // Symbol-level comparison
        const ext = std.fs.path.extension(file_path);
        const lang_query = symbols.languageForExtension(ext) orelse {
            // Unsupported language: fall back to full-file comparison
            if (!std.mem.eql(u8, historical_content.?, current_content)) {
                return staleChangedAfterSpec(allocator, cwd_path, anchor, file_path, provenance, detected_vcs);
            }
            return .{
                .label = try allocator.dupe(u8, "ok"),
                .display = anchor,
                .reason = try allocator.dupe(u8, ""),
            };
        };

        const current_fingerprint = symbols.fingerprintSymbolSyntax(current_content, lang_query, sym);
        if (current_fingerprint == null) {
            return .{
                .label = try allocator.dupe(u8, "STALE"),
                .display = anchor,
                .reason = try allocator.dupe(u8, "symbol not found"),
            };
        }

        const historical_fingerprint = symbols.fingerprintSymbolSyntax(historical_content.?, lang_query, sym);
        if (historical_fingerprint == null) {
            // Symbol didn't exist at provenance
            return staleChangedAfterSpec(allocator, cwd_path, anchor, file_path, provenance, detected_vcs);
        }

        if (current_fingerprint.? != historical_fingerprint.?) {
            return staleChangedAfterSpec(allocator, cwd_path, anchor, file_path, provenance, detected_vcs);
        }
    } else {
        // File-level comparison
        const ext = std.fs.path.extension(file_path);
        if (symbols.languageForExtension(ext)) |lang_query| {
            const current_fingerprint = symbols.fingerprintFileSyntax(current_content, lang_query);
            const historical_fingerprint = symbols.fingerprintFileSyntax(historical_content.?, lang_query);

            if (current_fingerprint == null or historical_fingerprint == null) {
                if (!std.mem.eql(u8, historical_content.?, current_content)) {
                    return staleChangedAfterSpec(allocator, cwd_path, anchor, file_path, provenance, detected_vcs);
                }
            } else if (current_fingerprint.? != historical_fingerprint.?) {
                return staleChangedAfterSpec(allocator, cwd_path, anchor, file_path, provenance, detected_vcs);
            }
        } else {
            if (!std.mem.eql(u8, historical_content.?, current_content)) {
                return staleChangedAfterSpec(allocator, cwd_path, anchor, file_path, provenance, detected_vcs);
            }
        }
    }

    return .{
        .label = try allocator.dupe(u8, "ok"),
        .display = anchor,
        .reason = try allocator.dupe(u8, ""),
    };
}

/// Build a STALE "changed after spec" status, enriched with blame info when available.
fn staleChangedAfterSpec(
    allocator: std.mem.Allocator,
    cwd_path: []const u8,
    anchor: []const u8,
    file_path: []const u8,
    provenance: []const u8,
    detected_vcs: vcs.VcsKind,
) !AnchorStatus {
    const blame = vcs.getBlameInfo(allocator, cwd_path, file_path, provenance, detected_vcs) catch null;
    errdefer if (blame) |b| b.deinit(allocator);

    const label = try allocator.dupe(u8, "STALE");
    errdefer allocator.free(label);
    const reason = try allocator.dupe(u8, "changed after spec");

    return .{
        .label = label,
        .display = anchor,
        .reason = reason,
        .blame = blame,
    };
}

fn runStatus(allocator: std.mem.Allocator, stdout_w: *std.io.Writer, stderr_w: *std.io.Writer) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse --format flag after "status" subcommand
    var format_json = false;
    var i: usize = 2; // skip binary path and "status"
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--format")) {
            if (i + 1 < args.len and std.mem.eql(u8, args[i + 1], "json")) {
                format_json = true;
                i += 1;
            }
        }
    }

    var specs: std.ArrayList(Spec) = .{};
    defer {
        for (specs.items) |*s| s.deinit(allocator);
        specs.deinit(allocator);
    }

    try loadSpecsWithInlineAnchors(allocator, &specs);

    if (format_json) {
        writeSpecsJson(stdout_w, specs.items);
    } else {
        writeSpecsText(stdout_w, specs.items);
    }

    _ = stderr_w;
}

fn writeSpecsText(w: *std.io.Writer, specs: []const Spec) void {
    if (specs.len == 0) return;

    for (specs, 0..) |spec, idx| {
        w.print("{s} ({d} anchor{s})\n", .{
            spec.path,
            spec.anchors.items.len,
            if (spec.anchors.items.len == 1) "" else "s",
        }) catch {};

        if (spec.anchors.items.len > 0) {
            w.print("  files:\n", .{}) catch {};
            for (spec.anchors.items) |anchor| {
                w.print("    - {s}\n", .{anchor}) catch {};
            }
        }

        if (idx < specs.len - 1) {
            w.print("\n", .{}) catch {};
        }
    }
}

fn writeSpecsJson(w: *std.io.Writer, specs: []const Spec) void {
    var json_w: std.json.Stringify = .{ .writer = w, .options = .{} };

    json_w.beginArray() catch return;
    for (specs) |spec| {
        json_w.write(.{
            .spec = spec.path,
            .files = spec.anchors.items,
        }) catch return;
    }
    json_w.endArray() catch return;
    w.writeByte('\n') catch {};
}

fn runUnlink(allocator: std.mem.Allocator, stdout_w: *std.io.Writer, stderr_w: *std.io.Writer) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // args[0] = binary path, args[1] = "unlink", args[2] = spec-path, args[3] = anchor
    if (args.len < 4) {
        stderr_w.print("usage: drift unlink <spec-path> <anchor>\n", .{}) catch {};
        return error.MissingArguments;
    }

    const spec_path = args[2];
    const anchor = args[3];

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

// --- link command ---

fn runLink(allocator: std.mem.Allocator, stdout_w: *std.io.Writer, stderr_w: *std.io.Writer) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // args[0] = binary path, args[1] = "link", args[2] = spec-path, args[3] = anchor (optional)
    if (args.len < 3) {
        stderr_w.print("usage: drift link <spec-path> [anchor]\n", .{}) catch {};
        return error.MissingArguments;
    }

    const spec_path = args[2];

    // Get current change ID for auto-provenance
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

    if (args.len >= 4) {
        // Targeted mode: drift link <spec-path> <anchor>
        const raw_anchor = args[3];

        // Auto-provenance: if no @change suffix, append current change ID
        const anchor = blk: {
            const identity = frontmatter.anchorFileIdentity(raw_anchor);
            if (identity.len != raw_anchor.len) {
                break :blk raw_anchor;
            }
            if (auto_change_id) |cid| {
                break :blk std.fmt.allocPrint(allocator, "{s}@{s}", .{ raw_anchor, cid }) catch break :blk raw_anchor;
            }
            break :blk raw_anchor;
        };
        const anchor_owned = anchor.ptr != raw_anchor.ptr;
        defer if (anchor_owned) allocator.free(anchor);

        // Update frontmatter anchor
        const after_frontmatter = try frontmatter.linkAnchor(allocator, content, anchor);
        defer allocator.free(after_frontmatter);

        // Update inline references matching this file
        const target_file = frontmatter.anchorFileIdentity(raw_anchor);
        // Strip #symbol from target_file to get just the file path for inline matching
        const target_hash_pos = std.mem.indexOfScalar(u8, target_file, '#');
        const target_path = if (target_hash_pos) |pos| target_file[0..pos] else target_file;

        const change_id = if (auto_change_id) |cid| cid else "unknown";
        const final_result = try scanner.updateInlineAnchors(allocator, after_frontmatter, target_path, change_id);
        defer allocator.free(final_result);

        const file = cwd.openFile(spec_path, .{ .mode = .write_only }) catch |err| {
            stderr_w.print("cannot write {s}: {s}\n", .{ spec_path, @errorName(err) }) catch {};
            return err;
        };
        defer file.close();

        try file.writeAll(final_result);
        try file.setEndPos(final_result.len);

        stdout_w.print("added {s} to {s}\n", .{ anchor, spec_path }) catch {};
    } else {
        // Blanket mode: drift link <spec-path>
        const change_id = auto_change_id orelse {
            stderr_w.print("cannot determine current change ID\n", .{}) catch {};
            return error.NoChangeId;
        };

        // Update all frontmatter anchors
        const after_frontmatter = try frontmatter.relinkAllAnchors(allocator, content, change_id);
        defer allocator.free(after_frontmatter);

        // Update all inline references
        const final_result = try scanner.updateInlineAnchors(allocator, after_frontmatter, null, change_id);
        defer allocator.free(final_result);

        const file = cwd.openFile(spec_path, .{ .mode = .write_only }) catch |err| {
            stderr_w.print("cannot write {s}: {s}\n", .{ spec_path, @errorName(err) }) catch {};
            return err;
        };
        defer file.close();

        try file.writeAll(final_result);
        try file.setEndPos(final_result.len);

        stdout_w.print("relinked all anchors in {s}\n", .{spec_path}) catch {};
    }
}
