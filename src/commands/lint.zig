const std = @import("std");
const frontmatter = @import("../frontmatter.zig");
const scanner = @import("../scanner.zig");
const symbols = @import("../symbols.zig");
const vcs = @import("../vcs.zig");

const Spec = scanner.Spec;

/// Caches current and historical file bytes for one lint run (path -> bytes, rev+path -> bytes).
const FileCache = struct {
    allocator: std.mem.Allocator,
    current: std.StringHashMap([]const u8),
    historical: std.StringHashMap([]const u8),

    fn init(allocator: std.mem.Allocator) FileCache {
        return .{
            .allocator = allocator,
            .current = std.StringHashMap([]const u8).init(allocator),
            .historical = std.StringHashMap([]const u8).init(allocator),
        };
    }

    fn deinit(self: *FileCache) void {
        var c_it = self.current.iterator();
        while (c_it.next()) |kv| {
            self.allocator.free(kv.key_ptr.*);
            self.allocator.free(kv.value_ptr.*);
        }
        self.current.deinit();
        var h_it = self.historical.iterator();
        while (h_it.next()) |kv| {
            self.allocator.free(kv.key_ptr.*);
            self.allocator.free(kv.value_ptr.*);
        }
        self.historical.deinit();
    }

    fn getCurrent(self: *FileCache, path: []const u8) ?[]const u8 {
        if (self.current.get(path)) |c| return c;
        const content = std.fs.cwd().readFileAlloc(self.allocator, path, 1024 * 1024) catch return null;
        const key = self.allocator.dupe(u8, path) catch {
            self.allocator.free(content);
            return null;
        };
        self.current.put(key, content) catch {
            self.allocator.free(key);
            self.allocator.free(content);
            return null;
        };
        return content;
    }

    fn getHistorical(self: *FileCache, cat_file: *vcs.GitCatFile, revision: []const u8, file_path: []const u8) !?[]const u8 {
        const key_str = try std.fmt.allocPrint(self.allocator, "{s}\x1f{s}", .{ revision, file_path });
        defer self.allocator.free(key_str);

        if (self.historical.get(key_str)) |c| return c;

        const content_opt = try cat_file.getContent(self.allocator, revision, file_path);
        if (content_opt == null) return null;
        const content = content_opt.?;

        const key_owned = try self.allocator.dupe(u8, key_str);
        errdefer self.allocator.free(key_owned);
        errdefer self.allocator.free(content);
        try self.historical.put(key_owned, content);
        return content;
    }
};

const AnchorStatus = struct {
    label: []const u8,
    display: []const u8,
    reason: []const u8,
    blame: ?vcs.BlameInfo = null,

    fn deinit(self: AnchorStatus, allocator: std.mem.Allocator) void {
        if (self.blame) |blame| blame.deinit(allocator);
    }
};

pub fn run(allocator: std.mem.Allocator, stdout_w: *std.io.Writer, stderr_w: *std.io.Writer) !void {
    var specs: std.ArrayList(Spec) = .{};
    defer {
        for (specs.items) |*s| s.deinit(allocator);
        specs.deinit(allocator);
    }

    try scanner.findAndSortSpecs(allocator, &specs);

    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);

    const detected_vcs = vcs.detectVcs();
    var has_issues = false;

    var file_cache = FileCache.init(allocator);
    defer file_cache.deinit();

    var cat_file = try vcs.GitCatFile.init(allocator, cwd_path);
    defer cat_file.deinit();

    const repo_identity = vcs.getRepoIdentity(allocator, cwd_path);
    defer if (repo_identity) |ri| allocator.free(ri);

    for (specs.items) |spec| {
        stdout_w.print("{s}\n", .{spec.path}) catch {};

        if (spec.anchors.items.len == 0) {
            stdout_w.print("  ok\n", .{}) catch {};
            continue;
        }

        if (spec.origin) |origin| {
            const is_local = if (repo_identity) |ri| std.mem.eql(u8, origin, ri) else false;
            if (!is_local) {
                for (spec.anchors.items) |anchor| {
                    stdout_w.print("  SKIP   {s} (origin: {s})\n", .{ anchor, origin }) catch {};
                }
                continue;
            }
        }

        const spec_commit = vcs.getLastCommit(allocator, cwd_path, spec.path, detected_vcs) catch |err| {
            stderr_w.print("vcs error for {s}: {s}\n", .{ spec.path, @errorName(err) }) catch {};
            return error.LintCheckFailed;
        };
        defer if (spec_commit) |c| allocator.free(c);

        var all_ok = true;

        for (spec.anchors.items) |anchor| {
            const status = checkAnchor(allocator, cwd_path, anchor, spec_commit, detected_vcs, &cat_file, &file_cache) catch |err| {
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

fn checkAnchor(
    allocator: std.mem.Allocator,
    cwd_path: []const u8,
    anchor: []const u8,
    spec_commit: ?[]const u8,
    detected_vcs: vcs.VcsKind,
    cat_file: *vcs.GitCatFile,
    file_cache: *FileCache,
) !AnchorStatus {
    const identity = frontmatter.anchorFileIdentity(anchor);
    const provenance: ?[]const u8 = if (identity.len < anchor.len)
        anchor[identity.len + 1 ..]
    else
        null;

    const hash_pos = std.mem.indexOfScalar(u8, identity, '#');
    const file_path = if (hash_pos) |pos| identity[0..pos] else identity;
    const symbol_name = if (hash_pos) |pos| identity[pos + 1 ..] else null;

    const file_exists = blk: {
        std.fs.cwd().access(file_path, .{}) catch break :blk false;
        break :blk true;
    };

    if (!file_exists) {
        return .{
            .label = "STALE",
            .display = anchor,
            .reason = "file not found",
        };
    }

    const needs_current_content = symbol_name != null or provenance != null or spec_commit != null;
    const file_content: ?[]const u8 = if (needs_current_content) blk: {
        break :blk file_cache.getCurrent(file_path) orelse {
            return .{
                .label = "STALE",
                .display = anchor,
                .reason = "file not readable",
            };
        };
    } else null;

    if (symbol_name) |sym| {
        const content = file_content.?;

        const ext = std.fs.path.extension(file_path);
        if (symbols.languageForExtension(ext)) |lang_query| {
            if (!symbols.resolveSymbolWithTreeSitter(content, lang_query, sym)) {
                return .{
                    .label = "STALE",
                    .display = anchor,
                    .reason = "symbol not found",
                };
            }
        } else {
            if (std.mem.indexOf(u8, content, sym) == null) {
                return .{
                    .label = "STALE",
                    .display = anchor,
                    .reason = "symbol not found",
                };
            }
        }
    }

    if (provenance) |prov| {
        if (std.mem.startsWith(u8, prov, "sig:")) {
            return checkAnchorBySig(allocator, cwd_path, anchor, file_path, symbol_name, prov["sig:".len..], spec_commit, detected_vcs, file_content.?);
        }
        return checkAnchorByContent(allocator, cwd_path, anchor, file_path, symbol_name, prov, spec_commit, detected_vcs, file_content.?, cat_file, file_cache);
    }
    if (spec_commit) |commit| {
        return checkAnchorByContent(allocator, cwd_path, anchor, file_path, symbol_name, commit, spec_commit, detected_vcs, file_content.?, cat_file, file_cache);
    }

    return .{
        .label = "ok",
        .display = anchor,
        .reason = "",
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
    current_content: []const u8,
    cat_file: *vcs.GitCatFile,
    file_cache: *FileCache,
) !AnchorStatus {
    const historical_content = blk: {
        const from_prov = file_cache.getHistorical(cat_file, provenance, file_path) catch break :blk null;
        if (from_prov) |content| break :blk content;
        if (spec_commit) |sc| {
            const from_spec = file_cache.getHistorical(cat_file, sc, file_path) catch break :blk null;
            if (from_spec) |content| break :blk content;
        }
        break :blk null;
    };

    if (historical_content == null) {
        return staleChangedAfterSpec(allocator, cwd_path, anchor, file_path, provenance, detected_vcs);
    }

    if (symbol_name) |sym| {
        const ext = std.fs.path.extension(file_path);
        const lang_query = symbols.languageForExtension(ext) orelse {
            if (!std.mem.eql(u8, historical_content.?, current_content)) {
                return staleChangedAfterSpec(allocator, cwd_path, anchor, file_path, provenance, detected_vcs);
            }
            return .{
                .label = "ok",
                .display = anchor,
                .reason = "",
            };
        };

        const current_fingerprint = symbols.fingerprintSymbolSyntax(current_content, lang_query, sym);
        if (current_fingerprint == null) {
            return .{
                .label = "STALE",
                .display = anchor,
                .reason = "symbol not found",
            };
        }

        const historical_fingerprint = symbols.fingerprintSymbolSyntax(historical_content.?, lang_query, sym);
        if (historical_fingerprint == null) {
            return staleChangedAfterSpec(allocator, cwd_path, anchor, file_path, provenance, detected_vcs);
        }

        if (current_fingerprint.? != historical_fingerprint.?) {
            return staleChangedAfterSpec(allocator, cwd_path, anchor, file_path, provenance, detected_vcs);
        }
    } else {
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
        .label = "ok",
        .display = anchor,
        .reason = "",
    };
}

fn checkAnchorBySig(
    allocator: std.mem.Allocator,
    cwd_path: []const u8,
    anchor: []const u8,
    file_path: []const u8,
    symbol_name: ?[]const u8,
    sig_hex: []const u8,
    spec_commit: ?[]const u8,
    detected_vcs: vcs.VcsKind,
    current_content: []const u8,
) !AnchorStatus {
    const fingerprint = symbols.computeFingerprint(current_content, file_path, symbol_name) orelse {
        return .{
            .label = "STALE",
            .display = anchor,
            .reason = "cannot compute fingerprint",
        };
    };

    var hex_buf: [16]u8 = undefined;
    const current_hex = std.fmt.bufPrint(&hex_buf, "{x:0>16}", .{fingerprint}) catch unreachable;

    if (std.mem.eql(u8, current_hex, sig_hex)) {
        return .{
            .label = "ok",
            .display = anchor,
            .reason = "",
        };
    }

    const blame_rev = spec_commit orelse sig_hex;
    const blame = vcs.getBlameInfo(allocator, cwd_path, file_path, blame_rev, detected_vcs) catch null;
    errdefer if (blame) |b| b.deinit(allocator);

    return .{
        .label = "STALE",
        .display = anchor,
        .reason = "changed after spec",
        .blame = blame,
    };
}

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

    return .{
        .label = "STALE",
        .display = anchor,
        .reason = "changed after spec",
        .blame = blame,
    };
}
