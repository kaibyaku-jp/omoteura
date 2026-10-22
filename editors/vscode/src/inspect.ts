import { execFile } from "node:child_process";
import type { Scene } from "./messages.ts";

// The JSON printed by `omoteura inspect` and `omoteura diagram`, format version 1.

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
  scene: Scene | null;
  shapes: Shape[];
  error: string | null;
}

export class InspectError extends Error {
  override name = "InspectError";
}

/** Runs a program without a shell and resolves with its standard output. */
export type Runner = (program: string, args: string[], options: { cwd: string }) => Promise<string>;

export const execRunner: Runner = (program, args, { cwd }) =>
  new Promise((resolve, reject) => {
    execFile(
      program,
      args,
      { cwd, timeout: 20_000, maxBuffer: 16 * 1024 * 1024, encoding: "utf8" },
      (error, stdout, stderr) => {
        if (error) {
          reject(new InspectError(stderr.trim() || error.message));
        } else {
          resolve(stdout);
        }
      },
    );
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

async function runOmoteura(
  command: readonly string[],
  root: string,
  subcommand: string,
  file: string,
  run: Runner,
): Promise<string> {
  const [program, ...base] = command;
  if (!program) {
    throw new InspectError("The omoteura.command setting is empty.");
  }
  return run(program, [...base, subcommand, file, "--root", root], { cwd: root });
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
