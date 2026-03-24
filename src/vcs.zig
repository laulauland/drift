const std = @import("std");

pub const VcsKind = enum { git, jj };

/// Detect whether the current working directory uses jj or git.
/// Always returns git for now — jj change IDs don't resolve in git-only CI,
/// and colocated repos have git underneath anyway. Re-enable when jj-native
/// forges exist and CI can resolve change IDs natively.
pub fn detectVcs() VcsKind {
    // TODO: re-enable jj detection when jj-native forges exist
    // std.fs.cwd().access(".jj", .{}) catch {
    //     return .git;
    // };
    // return .jj;
    return .git;
}

/// Get the last commit/change ID that touched a given file path.
pub fn getLastCommit(allocator: std.mem.Allocator, cwd_path: []const u8, file_path: []const u8, vcs: VcsKind) !?[]const u8 {
    const result = switch (vcs) {
        .git => try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "log", "-1", "--format=%H", "--", file_path },
            .cwd = cwd_path,
            .max_output_bytes = 256 * 1024,
        }),
        .jj => blk: {
            const revset = try std.fmt.allocPrint(allocator, "latest(::@ & file(\"{s}\"))", .{file_path});
            defer allocator.free(revset);
            break :blk try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "jj", "log", "-r", revset, "--no-graph", "-T", "change_id ++ \"\\n\"", "--color=never" },
                .cwd = cwd_path,
                .max_output_bytes = 256 * 1024,
            });
        },
    };
    defer allocator.free(result.stderr);

    const stdout = result.stdout;
    if (stdout.len == 0) {
        allocator.free(stdout);
        return null;
    }

    // Trim trailing newline
    const trimmed = std.mem.trimRight(u8, stdout, "\n\r ");
    if (trimmed.len == 0) {
        allocator.free(stdout);
        return null;
    }

    const commit = try allocator.dupe(u8, trimmed);
    allocator.free(stdout);
    return commit;
}

/// Check if a bound file was modified after the given commit/change.
pub fn checkStaleness(
    allocator: std.mem.Allocator,
    cwd_path: []const u8,
    spec_commit: []const u8,
    bound_file: []const u8,
    vcs: VcsKind,
) !bool {
    const result = switch (vcs) {
        .git => blk: {
            const range = try std.fmt.allocPrint(allocator, "{s}..HEAD", .{spec_commit});
            defer allocator.free(range);
            break :blk try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "git", "log", "--oneline", range, "--", bound_file },
                .cwd = cwd_path,
                .max_output_bytes = 256 * 1024,
            });
        },
        .jj => blk: {
            const revset = try std.fmt.allocPrint(allocator, "{s}..@ & file(\"{s}\")", .{ spec_commit, bound_file });
            defer allocator.free(revset);
            break :blk try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "jj", "log", "-r", revset, "--no-graph", "-T", "change_id ++ \"\\n\"", "--color=never" },
                .cwd = cwd_path,
                .max_output_bytes = 256 * 1024,
            });
        },
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const trimmed = std.mem.trimRight(u8, result.stdout, "\n\r ");
    return trimmed.len > 0;
}

/// Get file content at a specific revision. Returns null if the file didn't exist at that revision.
/// Caller owns returned memory.
pub fn getFileAtRevision(
    allocator: std.mem.Allocator,
    cwd_path: []const u8,
    revision: []const u8,
    file_path: []const u8,
    vcs_kind: VcsKind,
) !?[]const u8 {
    const rev_path = switch (vcs_kind) {
        .git => try std.fmt.allocPrint(allocator, "{s}:{s}", .{ revision, file_path }),
        .jj => null,
    };
    defer if (rev_path) |rp| allocator.free(rp);

    const argv: []const []const u8 = switch (vcs_kind) {
        .git => &.{ "git", "show", rev_path.? },
        .jj => &.{ "jj", "file", "show", "-r", revision, file_path },
    };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd_path,
        .max_output_bytes = 1024 * 1024,
    }) catch return null;
    defer allocator.free(result.stderr);

    // Non-zero exit means the file didn't exist at that revision
    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                allocator.free(result.stdout);
                return null;
            }
        },
        else => {
            allocator.free(result.stdout);
            return null;
        },
    }

    return result.stdout;
}

/// Information about the most recent commit that changed a file after a given revision.
pub const BlameInfo = struct {
    author: []const u8,
    commit_hash: []const u8,
    date: []const u8,
    subject: []const u8,

    pub fn deinit(self: BlameInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.author);
        allocator.free(self.commit_hash);
        allocator.free(self.date);
        allocator.free(self.subject);
    }
};

/// Get blame info for the most recent commit that changed a file after a given revision.
/// Returns null if no commits changed the file after the revision.
/// Caller owns the returned BlameInfo and must call deinit on it.
pub fn getBlameInfo(
    allocator: std.mem.Allocator,
    cwd_path: []const u8,
    file_path: []const u8,
    after_revision: []const u8,
    vcs_kind: VcsKind,
) !?BlameInfo {
    switch (vcs_kind) {
        .git => {
            const range = try std.fmt.allocPrint(allocator, "{s}..HEAD", .{after_revision});
            defer allocator.free(range);

            const result = std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "git", "log", "-1", "--format=%an%n%h%n%ad%n%s", "--date=format:%b %d", range, "--", file_path },
                .cwd = cwd_path,
                .max_output_bytes = 256 * 1024,
            }) catch return null;
            defer allocator.free(result.stderr);

            const stdout = result.stdout;
            defer allocator.free(stdout);

            const trimmed = std.mem.trimRight(u8, stdout, "\n\r ");
            if (trimmed.len == 0) return null;

            // Parse four newline-delimited fields: author, hash, date, subject
            var lines = std.mem.splitScalar(u8, trimmed, '\n');
            const author_raw = lines.next() orelse return null;
            const hash_raw = lines.next() orelse return null;
            const date_raw = lines.next() orelse return null;
            const subject_raw = lines.rest();
            if (subject_raw.len == 0) return null;

            const author = try allocator.dupe(u8, author_raw);
            errdefer allocator.free(author);
            const commit_hash = try allocator.dupe(u8, hash_raw);
            errdefer allocator.free(commit_hash);
            const date = try allocator.dupe(u8, date_raw);
            errdefer allocator.free(date);
            const subject = try allocator.dupe(u8, subject_raw);

            return .{
                .author = author,
                .commit_hash = commit_hash,
                .date = date,
                .subject = subject,
            };
        },
        .jj => return null, // jj support disabled
    }
}

/// Get the current change/commit ID (short form) for auto-provenance.
pub fn getCurrentChangeId(allocator: std.mem.Allocator, cwd_path: []const u8, vcs: VcsKind) !?[]const u8 {
    const result = switch (vcs) {
        .git => try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "rev-parse", "--short", "HEAD" },
            .cwd = cwd_path,
            .max_output_bytes = 256 * 1024,
        }),
        .jj => try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "jj", "log", "-r", "@", "--no-graph", "-T", "change_id.shortest(8)", "--color=never" },
            .cwd = cwd_path,
            .max_output_bytes = 256 * 1024,
        }),
    };
    defer allocator.free(result.stderr);

    const stdout = result.stdout;
    if (stdout.len == 0) {
        allocator.free(stdout);
        return null;
    }

    const trimmed = std.mem.trimRight(u8, stdout, "\n\r ");
    if (trimmed.len == 0) {
        allocator.free(stdout);
        return null;
    }

    const id = try allocator.dupe(u8, trimmed);
    allocator.free(stdout);
    return id;
}
