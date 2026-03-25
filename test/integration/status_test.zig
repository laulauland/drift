const std = @import("std");
const helpers = @import("helpers");

test "status shows spec with its anchors" {
    const allocator = std.testing.allocator;
    var repo = try helpers.TempRepo.init(allocator);
    defer repo.cleanup();

    try repo.writeSpec("docs/auth.md", &.{ "src/auth/login.ts", "src/auth/provider.ts" }, "# Auth spec\n");
    try repo.writeFile("src/auth/login.ts", "export function login() {}\n");
    try repo.writeFile("src/auth/provider.ts", "export class Provider {}\n");
    try repo.commit("add spec and source files");

    const result = try repo.runDrift(&.{"status"});
    defer result.deinit(allocator);

    try helpers.expectContains(result.stdout, "docs/auth.md");
    try helpers.expectContains(result.stdout, "src/auth/login.ts");
    try helpers.expectContains(result.stdout, "src/auth/provider.ts");
}

test "status shows provenance on anchors" {
    const allocator = std.testing.allocator;
    var repo = try helpers.TempRepo.init(allocator);
    defer repo.cleanup();

    try repo.writeSpec("docs/spec.md", &.{"src/file.ts@qpvuntsm"}, "# Spec\n");
    try repo.writeFile("src/file.ts", "export const x = 1;\n");
    try repo.commit("add spec with provenance");

    const result = try repo.runDrift(&.{"status"});
    defer result.deinit(allocator);

    try helpers.expectContains(result.stdout, "@qpvuntsm");
}

test "status shows no specs when none exist" {
    const allocator = std.testing.allocator;
    var repo = try helpers.TempRepo.init(allocator);
    defer repo.cleanup();

    try repo.writeFile("README.md", "# Hello\n");
    try repo.commit("add readme only");

    const result = try repo.runDrift(&.{"status"});
    defer result.deinit(allocator);

    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should indicate no specs found — exact wording TBD
    _ = output;
    try helpers.expectExitCode(result.term, 0);
}

test "status includes inline anchors from spec body" {
    const allocator = std.testing.allocator;
    var repo = try helpers.TempRepo.init(allocator);
    defer repo.cleanup();

    const body =
        \\# Spec
        \\
        \\References @./src/helper.ts in the body.
        \\
    ;
    try repo.writeSpec("docs/spec.md", &.{}, body);
    try repo.writeFile("src/helper.ts", "export function help() {}\n");
    try repo.commit("add spec with inline anchor");

    const result = try repo.runDrift(&.{"status"});
    defer result.deinit(allocator);

    try helpers.expectContains(result.stdout, "docs/spec.md");
    try helpers.expectContains(result.stdout, "src/helper.ts");
    try helpers.expectContains(result.stdout, "1 anchor");
}

test "status format json outputs valid escaped json" {
    const allocator = std.testing.allocator;
    var repo = try helpers.TempRepo.init(allocator);
    defer repo.cleanup();

    try repo.writeSpec("docs/spec\"name.md", &.{"src/main\"file.ts"}, "# Spec\n");
    try repo.writeFile("src/main\"file.ts", "export function main() {}\n");
    try repo.commit("add spec and source with quoted paths");

    const result = try repo.runDrift(&.{ "status", "--format", "json" });
    defer result.deinit(allocator);

    const StatusEntry = struct {
        spec: []const u8,
        files: []const []const u8,
    };

    var parsed = try std.json.parseFromSlice([]StatusEntry, allocator, result.stdout, .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.value.len);
    try std.testing.expectEqualStrings("docs/spec\"name.md", parsed.value[0].spec);
    try std.testing.expectEqual(@as(usize, 1), parsed.value[0].files.len);
    try std.testing.expectEqualStrings("src/main\"file.ts", parsed.value[0].files[0]);
}
