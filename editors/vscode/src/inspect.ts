import { execFile } from "node:child_process";
import type { Scene } from "./messages.ts";

// The JSON printed by `omoteura inspect`, `diagram`, `coverage` and `save`, format version 1.

export type TestStatus = "passed" | "failed" | "pending";

export interface Target {
  path: string;
  start_line: number;
  end_line: number;
}

export interface ExampleResult {
  line_number: number;
  full_description: string;
  status: TestStatus;
  message: string | null;
}

export interface Shape {
  id: string;
  label: string | null;
  link: string;
  target: Target | null;
  error: string | null;
  test: { status: TestStatus; examples: ExampleResult[] } | null;
}

export interface Attachment {
  diagram_path: string;
  source: "magic_comment" | "config" | "convention";
  missing: boolean;
}

export interface Report {
  version: 1;
  code_path: string;
  new_diagram_path: string;
  attachment: Attachment | null;
  shapes: Shape[];
  error: string | null;
}

export interface DiagramReport {
  version: 1;
  diagram_path: string;
  /** Code files the diagram is attached to; links without a path resolve against the first. */
  attached_to: string[];
  /** SHA-256 of the file as read, to save only over that version. */
  digest: string | null;
  scene: Scene | null;
  shapes: Shape[];
  error: string | null;
}

export interface CoveredExample {
  path: string;
  line: number;
  description: string;
  status: TestStatus | null;
}

export interface CoverageItem {
  kind: "validations" | "associations" | "callbacks" | "scopes" | "enums" | "methods";
  /** The declaration's first line, or the method's name. */
  name: string;
  start_line: number;
  end_line: number;
  covered: boolean;
  /** Whether a method's body ran in the last test run; null when that cannot be told. */
  executed: boolean | null;
  examples: CoveredExample[];
}

export interface CoverageReport {
  version: 1;
  code_path: string;
  /** False when .omoteura.yml turns the coverage panel off. */
  enabled: boolean;
  spec_paths: string[];
  items: CoverageItem[];
}

export interface SaveResult {
  version: 1;
  diagram_path: string | null;
  /** SHA-256 of what was written. */
  digest: string | null;
  error: string | null;
  /** True when the file changed since it was read, so nothing was written. */
  conflict: boolean;
}

export class InspectError extends Error {
  override name = "InspectError";
}

export interface RunOptions {
  cwd: string;
  /** Written to the program's standard input. */
  input?: string;
  /** Exit statuses besides 0 that still mean the output is the answer. */
  okStatuses?: readonly number[];
}

/** Runs a program without a shell and resolves with its standard output. */
export type Runner = (program: string, args: string[], options: RunOptions) => Promise<string>;

export const execRunner: Runner = (program, args, { cwd, input, okStatuses = [] }) =>
  new Promise((resolve, reject) => {
    const child = execFile(
      program,
      args,
      { cwd, timeout: 20_000, maxBuffer: 16 * 1024 * 1024, encoding: "utf8" },
      (error, stdout, stderr) => {
        if (error && !(typeof error.code === "number" && okStatuses.includes(error.code))) {
          reject(new InspectError(stderr.trim() || error.message));
        } else {
          resolve(stdout);
        }
      },
    );
    if (input !== undefined) {
      // A program that failed to start closes its input; the callback reports why.
      child.stdin?.on("error", () => {});
      child.stdin?.end(input);
    }
  });

/**
 * Asks omoteura about one code file. command is the configured way to run
 * omoteura, such as ["bundle", "exec", "omoteura"].
 */
export async function inspect(
  command: readonly string[],
  root: string,
  file: string,
  run: Runner = execRunner,
): Promise<Report> {
  return parseReport(await runOmoteura(command, root, "inspect", file, run));
}

/** Asks omoteura about one diagram file. */
export async function inspectDiagram(
  command: readonly string[],
  root: string,
  file: string,
  run: Runner = execRunner,
): Promise<DiagramReport> {
  return parseDiagramReport(await runOmoteura(command, root, "diagram", file, run));
}

/** Asks omoteura which declarations and methods of one code file its specs cover. */
export async function inspectCoverage(
  command: readonly string[],
  root: string,
  file: string,
  run: Runner = execRunner,
): Promise<CoverageReport> {
  return parseCoverageReport(await runOmoteura(command, root, "coverage", file, run));
}

/**
 * Saves a drawing, as Excalidraw serializes it, to file in the file's own
 * format. With ifUnchanged, the digest of the file as it was read, nothing
 * is written over a change made since; the result says so.
 */
export async function saveDiagram(
  command: readonly string[],
  root: string,
  file: string,
  drawing: string,
  ifUnchanged: string | null,
  run: Runner = execRunner,
): Promise<SaveResult> {
  const extra = ifUnchanged ? ["--if-unchanged", ifUnchanged] : [];
  // omoteura save exits 1, printing why, when it refuses to write.
  return parseSaveResult(
    await runOmoteura(command, root, "save", file, run, extra, { input: drawing, okStatuses: [1] }),
  );
}

async function runOmoteura(
  command: readonly string[],
  root: string,
  subcommand: string,
  file: string,
  run: Runner,
  extra: readonly string[] = [],
  options: Omit<RunOptions, "cwd"> = {},
): Promise<string> {
  const [program, ...base] = command;
  if (!program) {
    throw new InspectError("The omoteura.command setting is empty.");
  }
  return run(program, [...base, subcommand, file, "--root", root, ...extra], { cwd: root, ...options });
}

export function parseReport(output: string): Report {
  const data = parseJson(output, "inspect");
  if (data.version !== 1 || !Array.isArray(data.shapes) || typeof data.code_path !== "string") {
    throw unsupported("inspect");
  }
  return data as unknown as Report;
}

export function parseDiagramReport(output: string): DiagramReport {
  const data = parseJson(output, "diagram");
  if (data.version !== 1 || !Array.isArray(data.shapes) || !Array.isArray(data.attached_to)) {
    throw unsupported("diagram");
  }
  return data as unknown as DiagramReport;
}

export function parseCoverageReport(output: string): CoverageReport {
  const data = parseJson(output, "coverage");
  if (data.version !== 1 || !Array.isArray(data.items) || typeof data.enabled !== "boolean") {
    throw unsupported("coverage");
  }
  return data as unknown as CoverageReport;
}

export function parseSaveResult(output: string): SaveResult {
  const data = parseJson(output, "save");
  if (data.version !== 1 || typeof data.conflict !== "boolean") {
    throw unsupported("save");
  }
  return data as unknown as SaveResult;
}

function parseJson(output: string, subcommand: string): Record<string, unknown> {
  let data: unknown;
  try {
    data = JSON.parse(output);
  } catch {
    throw new InspectError(`omoteura ${subcommand} did not print JSON: ${output.slice(0, 200)}`);
  }
  if (!isObject(data)) {
    throw unsupported(subcommand);
  }
  return data;
}

function unsupported(subcommand: string): InspectError {
  return new InspectError(
    `omoteura ${subcommand} printed a format this extension does not understand. Update the omoteura gem and the extension to matching versions.`,
  );
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
