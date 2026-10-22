import { execFile } from "node:child_process";

// The JSON printed by `omoteura inspect`, format version 1.

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
  const [program, ...base] = command;
  if (!program) {
    throw new InspectError("The omoteura.command setting is empty.");
  }
  const output = await run(program, [...base, "inspect", file, "--root", root], { cwd: root });
  return parseReport(output);
}

export function parseReport(output: string): Report {
  let data: unknown;
  try {
    data = JSON.parse(output);
  } catch {
    throw new InspectError(`omoteura inspect did not print JSON: ${output.slice(0, 200)}`);
  }
  if (!isObject(data) || data.version !== 1 || !Array.isArray(data.shapes) || typeof data.code_path !== "string") {
    throw new InspectError(
      "omoteura inspect printed a format this extension does not understand. Update the omoteura gem and the extension to matching versions.",
    );
  }
  return data as unknown as Report;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
