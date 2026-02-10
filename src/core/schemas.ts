import { Schema } from "effect";

export const AgentBackend = Schema.Literal("claude", "pi", "codex");
export type AgentBackend = typeof AgentBackend.Type;
export type AgentBackendEncoded = typeof AgentBackend.Encoded;

export const VcsBackend = Schema.Literal("auto", "git", "jj");
export type VcsBackend = typeof VcsBackend.Type;
export type VcsBackendEncoded = typeof VcsBackend.Encoded;

export const VcsConfig = Schema.Struct({
  backend: Schema.optionalWith(VcsBackend, { default: () => "auto" }),
});
export type VcsConfig = typeof VcsConfig.Type;
export type VcsConfigEncoded = typeof VcsConfig.Encoded;

export const ExecutionConfig = Schema.Struct({
  parallel: Schema.optionalWith(Schema.Boolean, { default: () => false }),
});
export type ExecutionConfig = typeof ExecutionConfig.Type;
export type ExecutionConfigEncoded = typeof ExecutionConfig.Encoded;

export const DependencyResolver = Schema.Literal("explicit", "linear", "inferred");
export type DependencyResolver = typeof DependencyResolver.Type;
export type DependencyResolverEncoded = typeof DependencyResolver.Encoded;

export const DriftConfig = Schema.Struct({
  agent: Schema.optionalWith(AgentBackend, { default: () => "claude" }),
  model: Schema.NullOr(Schema.String),
  resolver: Schema.optionalWith(DependencyResolver, { default: () => "explicit" }),
  vcs: Schema.optionalWith(VcsConfig, { default: () => ({ backend: "auto" }) }),
  execution: Schema.optionalWith(ExecutionConfig, { default: () => ({ parallel: false }) }),
});
export type DriftConfig = typeof DriftConfig.Type;
export type DriftConfigEncoded = typeof DriftConfig.Encoded;

export const ImportKind = Schema.Literal("file", "glob", "range", "symbol");
export type ImportKind = typeof ImportKind.Type;
export type ImportKindEncoded = typeof ImportKind.Encoded;

export const Import = Schema.Struct({
  raw: Schema.String,
  kind: ImportKind,
  path: Schema.String,
  range: Schema.optional(Schema.Tuple(Schema.Number, Schema.Number)),
  symbol: Schema.optional(Schema.String),
});
export type Import = typeof Import.Type;
export type ImportEncoded = typeof Import.Encoded;

export const Inline = Schema.Struct({
  raw: Schema.String,
  command: Schema.String,
});
export type Inline = typeof Inline.Type;
export type InlineEncoded = typeof Inline.Encoded;

export const CellState = Schema.Literal("clean", "stale", "running", "error");
export type CellState = typeof CellState.Type;
export type CellStateEncoded = typeof CellState.Encoded;

export const BuildArtifact = Schema.Struct({
  files: Schema.Array(Schema.String),
  ref: Schema.NullOr(Schema.String),
  timestamp: Schema.String,
  summary: Schema.String,
  patch: Schema.String,
});
export type BuildArtifact = typeof BuildArtifact.Type;
export type BuildArtifactEncoded = typeof BuildArtifact.Encoded;

export const Cell = Schema.Struct({
  index: Schema.Number,
  content: Schema.String,
  explicitDeps: Schema.NullOr(Schema.Array(Schema.Number)),
  agent: Schema.NullOr(AgentBackend),
  imports: Schema.Array(Import),
  inlines: Schema.Array(Inline),
  version: Schema.Number,
  dependencies: Schema.Array(Schema.Number),
  dependents: Schema.Array(Schema.Number),
  state: CellState,
  comments: Schema.Array(Schema.String),
  artifact: Schema.NullOr(BuildArtifact),
  lastInputHash: Schema.NullOr(Schema.String),
});
export type Cell = typeof Cell.Type;
export type CellEncoded = typeof Cell.Encoded;

export const decodeAgentBackend = Schema.decodeUnknownEither(AgentBackend);
export const encodeAgentBackend = Schema.encodeEither(AgentBackend);

export const decodeVcsBackend = Schema.decodeUnknownEither(VcsBackend);
export const encodeVcsBackend = Schema.encodeEither(VcsBackend);

export const decodeVcsConfig = Schema.decodeUnknownEither(VcsConfig);
export const encodeVcsConfig = Schema.encodeEither(VcsConfig);

export const decodeExecutionConfig = Schema.decodeUnknownEither(ExecutionConfig);
export const encodeExecutionConfig = Schema.encodeEither(ExecutionConfig);

export const decodeDependencyResolver = Schema.decodeUnknownEither(DependencyResolver);
export const encodeDependencyResolver = Schema.encodeEither(DependencyResolver);

export const decodeDriftConfig = Schema.decodeUnknownEither(DriftConfig);
export const encodeDriftConfig = Schema.encodeEither(DriftConfig);

export const decodeImportKind = Schema.decodeUnknownEither(ImportKind);
export const encodeImportKind = Schema.encodeEither(ImportKind);

export const decodeImport = Schema.decodeUnknownEither(Import);
export const encodeImport = Schema.encodeEither(Import);

export const decodeInline = Schema.decodeUnknownEither(Inline);
export const encodeInline = Schema.encodeEither(Inline);

export const decodeCellState = Schema.decodeUnknownEither(CellState);
export const encodeCellState = Schema.encodeEither(CellState);

export const decodeBuildArtifact = Schema.decodeUnknownEither(BuildArtifact);
export const encodeBuildArtifact = Schema.encodeEither(BuildArtifact);

export const decodeCell = Schema.decodeUnknownEither(Cell);
export const encodeCell = Schema.encodeEither(Cell);
