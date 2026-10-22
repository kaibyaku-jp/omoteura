import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  draftDiagram,
  execRunner,
  InspectError,
  inspect,
  inspectDiagram,
  parseDiagramReport,
  parseReport,
  type Runner,
  saveDiagram,
} from "../../src/inspect.ts";

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

describe("inspectDiagram", () => {
  it("runs the diagram command for the file", async () => {
    let args: string[] = [];
    const run: Runner = async (_program, given) => {
      args = given;
      return JSON.stringify({
        version: 1,
        diagram_path: "ura/a.excalidraw",
        attached_to: [],
        scene: null,
        shapes: [],
        error: null,
      });
    };

    const result = await inspectDiagram(["omoteura"], "/project", "/project/ura/a.excalidraw", run);

    assert.deepEqual(args, ["diagram", "/project/ura/a.excalidraw", "--root", "/project"]);
    assert.equal(result.diagram_path, "ura/a.excalidraw");
  });

  it("rejects a report without the files the diagram is attached to", () => {
    assert.throws(
      () => parseDiagramReport(JSON.stringify({ version: 1, shapes: [] })),
      /omoteura diagram printed a format this extension does not understand/,
    );
  });
});

describe("saveDiagram", () => {
  const saved = { version: 1, diagram_path: "ura/a.excalidraw", digest: "abc", error: null, conflict: false };

  it("sends the drawing on stdin with the digest it was read at", async () => {
    const calls: unknown[] = [];
    const run: Runner = async (program, args, options) => {
      calls.push({ program, args, options });
      return JSON.stringify(saved);
    };

    const result = await saveDiagram(
      ["omoteura"],
      "/project",
      "/project/ura/a.excalidraw",
      '{"elements":[]}',
      "d1",
      run,
    );

    assert.deepEqual(calls, [
      {
        program: "omoteura",
        args: ["save", "/project/ura/a.excalidraw", "--root", "/project", "--if-unchanged", "d1"],
        options: { cwd: "/project", input: '{"elements":[]}', okStatuses: [1] },
      },
    ]);
    assert.equal(result.digest, "abc");
  });

  it("leaves out --if-unchanged for a new file", async () => {
    let args: string[] = [];
    const run: Runner = async (_program, given) => {
      args = given;
      return JSON.stringify(saved);
    };

    await saveDiagram(["omoteura"], "/project", "/project/ura/b.excalidraw", "{}", null, run);

    assert.deepEqual(args, ["save", "/project/ura/b.excalidraw", "--root", "/project"]);
  });
});

describe("execRunner", () => {
  const echo =
    "process.stdin.pipe(process.stdout); process.stdin.on('end', () => { process.exitCode = Number(process.argv[1]); });";

  it("writes input to the program and resolves with what it prints", async () => {
    assert.equal(await execRunner(process.execPath, ["-e", echo, "0"], { cwd: ".", input: "表と裏" }), "表と裏");
  });

  it("resolves on an exit status the caller accepts, and rejects on others", async () => {
    assert.equal(
      await execRunner(process.execPath, ["-e", echo, "1"], { cwd: ".", input: "refused", okStatuses: [1] }),
      "refused",
    );
    await assert.rejects(
      execRunner(process.execPath, ["-e", echo, "2"], { cwd: ".", input: "x", okStatuses: [1] }),
      InspectError,
    );
  });
});

describe("draftDiagram", () => {
  const written = {
    code_path: "app/models/user.rb",
    diagram_path: "ura/app/models/user.excalidraw.md",
    shape_count: 2,
    status: "written",
  };

  it("drafts with --json, in the format asked for", async () => {
    let args: string[] = [];
    const run: Runner = async (_program, given) => {
      args = given;
      return JSON.stringify({ version: 1, results: [written] });
    };

    const result = await draftDiagram(
      ["omoteura"],
      "/project",
      "/project/app/models/user.rb",
      { merge: false, format: "obsidian" },
      run,
    );

    assert.deepEqual(args, ["draft", "/project/app/models/user.rb", "--root", "/project", "--json", "--format", "md"]);
    assert.deepEqual(result, written);
  });

  it("merges in the diagram's own format", async () => {
    let args: string[] = [];
    const run: Runner = async (_program, given) => {
      args = given;
      return JSON.stringify({ version: 1, results: [{ ...written, status: "merged" }] });
    };

    await draftDiagram(
      ["omoteura"],
      "/project",
      "/project/app/models/user.rb",
      { merge: true, format: "obsidian" },
      run,
    );

    assert.deepEqual(args.slice(4), ["--json", "--merge"]);
  });

  it("rejects output it does not understand", async () => {
    const run: Runner = async () => JSON.stringify({ version: 2, results: [] });

    await assert.rejects(
      draftDiagram(["omoteura"], "/p", "/p/a.rb", { merge: false, format: "excalidraw" }, run),
      /does not understand/,
    );
  });
});
