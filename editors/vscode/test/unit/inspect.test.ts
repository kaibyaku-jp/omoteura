import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { InspectError, inspect, parseReport, type Runner } from "../../src/inspect.ts";

const report = {
  version: 1,
  code_path: "app/models/user.rb",
  new_diagram_path: "ura/app/models/user.excalidraw",
  attachment: null,
  shapes: [],
  error: null,
};

describe("inspect", () => {
  it("runs the configured command with inspect, the file and the root, from the root", async () => {
    const calls: unknown[] = [];
    const run: Runner = async (program, args, options) => {
      calls.push({ program, args, options });
      return JSON.stringify(report);
    };

    const result = await inspect(["bundle", "exec", "omoteura"], "/project", "/project/app/models/user.rb", run);

    assert.deepEqual(calls, [
      {
        program: "bundle",
        args: ["exec", "omoteura", "inspect", "/project/app/models/user.rb", "--root", "/project"],
        options: { cwd: "/project" },
      },
    ]);
    assert.equal(result.code_path, "app/models/user.rb");
  });

  it("rejects an empty command", async () => {
    await assert.rejects(inspect([], "/project", "/project/a.rb"), InspectError);
  });

  it("passes failures of the command on", async () => {
    const run: Runner = async () => {
      throw new InspectError("omoteura: diagrams_dir must be a relative path");
    };

    await assert.rejects(inspect(["omoteura"], "/project", "/project/a.rb", run), /diagrams_dir/);
  });
});

describe("parseReport", () => {
  it("rejects output that is not JSON", () => {
    assert.throws(() => parseReport("Could not find gem 'omoteura'"), /did not print JSON: Could not find gem/);
  });

  it("rejects another format version", () => {
    assert.throws(
      () => parseReport(JSON.stringify({ ...report, version: 2 })),
      /format this extension does not understand/,
    );
  });
});
