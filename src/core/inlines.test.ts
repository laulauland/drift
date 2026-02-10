import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { parseInlines, resolveInlinesInContent } from "./inlines.ts";

const tempDirs: string[] = [];

const createTempProject = (): string => {
  const directory = mkdtempSync(join(tmpdir(), "drift-inlines-"));
  tempDirs.push(directory);
  return directory;
};

afterEach(() => {
  for (const directory of tempDirs.splice(0, tempDirs.length)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("inlines", () => {
  test("parseInlines ignores fenced code blocks", () => {
    const content = ["!`echo before`", "```bash", "!`echo ignored`", "```", "!`echo after`"].join(
      "\n",
    );

    expect(parseInlines(content)).toEqual([
      {
        raw: "!`echo before`",
        command: "echo before",
      },
      {
        raw: "!`echo after`",
        command: "echo after",
      },
    ]);
  });

  test("resolveInlinesInContent executes commands in the project root", () => {
    const projectRoot = createTempProject();

    const result = resolveInlinesInContent({
      cellIndex: 3,
      projectRoot,
      content: "cwd: !`pwd`",
    });

    expect(result.ok).toBeTrue();
    if (!result.ok) {
      return;
    }

    expect(result.value).toContain(projectRoot);
  });

  test("resolveInlinesInContent returns InlineCommandError on non-zero exits", () => {
    const projectRoot = createTempProject();

    const result = resolveInlinesInContent({
      cellIndex: 5,
      projectRoot,
      content: "!`echo boom 1>&2; exit 7`",
    });

    expect(result.ok).toBeFalse();
    if (result.ok) {
      return;
    }

    expect(result.error._tag).toBe("InlineCommandError");
    expect(result.error.cellIndex).toBe(5);
    expect(result.error.command).toBe("echo boom 1>&2; exit 7");
    expect(result.error.exitCode).toBe(7);
    expect(result.error.stderr).toContain("boom");
  });
});
