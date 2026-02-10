import { describe, expect, test } from "bun:test";
import { Either } from "effect";

import {
  decodeCell,
  decodeDriftConfig,
  encodeCell,
  type Cell,
  type DriftConfig,
} from "./schemas.ts";

describe("schemas", () => {
  test("decodeDriftConfig applies schema defaults", () => {
    const result = decodeDriftConfig({
      model: null,
    });

    expect(Either.isRight(result)).toBe(true);
    if (Either.isLeft(result)) {
      return;
    }

    const expected: DriftConfig = {
      agent: "claude",
      model: null,
      resolver: "explicit",
      vcs: {
        backend: "auto",
      },
      execution: {
        parallel: false,
      },
    };

    expect(result.right).toEqual(expected);
  });

  test("cell schema round-trips through decode/encode helpers", () => {
    const source: Cell = {
      index: 4,
      content: "Implement feature X",
      explicitDeps: [1, 2],
      agent: "pi",
      imports: [
        {
          raw: "@./src/core/schemas.ts",
          kind: "file",
          path: "./src/core/schemas.ts",
        },
      ],
      inlines: [
        {
          raw: "!`bun test`",
          command: "bun test",
        },
      ],
      version: 3,
      dependencies: [1, 2],
      dependents: [5],
      state: "clean",
      comments: ["Looks good"],
      artifact: {
        files: ["src/core/schemas.ts"],
        ref: null,
        timestamp: "2026-02-10T15:00:00.000Z",
        summary: "Added schema helpers",
        patch: "diff --git a/src/core/schemas.ts b/src/core/schemas.ts",
      },
      lastInputHash: "abc123",
    };

    const decoded = decodeCell(source);
    expect(Either.isRight(decoded)).toBe(true);
    if (Either.isLeft(decoded)) {
      return;
    }

    const encoded = encodeCell(decoded.right);
    expect(Either.isRight(encoded)).toBe(true);
    if (Either.isLeft(encoded)) {
      return;
    }

    expect(encoded.right).toEqual(source);
  });
});
