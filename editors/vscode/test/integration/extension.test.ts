import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import * as vscode from "vscode";
import type { OmoteuraApi } from "../../src/extension.ts";

// Runs inside VS Code with .vscode-test/sample_project open; see prepare.mjs.

const workspace = vscode.workspace.workspaceFolders?.[0]?.uri;
let api: OmoteuraApi;

function file(relative: string): vscode.Uri {
  assert.ok(workspace, "the sample project should be open");
  return vscode.Uri.joinPath(workspace, relative);
}

/** Resolves on the next refresh of uri after which ready() holds. */
function refreshOf(uri: vscode.Uri, ready: () => boolean = () => true): Promise<void> {
  return new Promise((resolve) => {
    const listener = api.onDidRefresh((refreshed) => {
      if (refreshed.toString() === uri.toString() && ready()) {
        listener.dispose();
        resolve();
      }
    });
  });
}

async function show(uri: vscode.Uri): Promise<void> {
  await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(uri));
}

function activeTabUri(): string | undefined {
  const input = vscode.window.tabGroups.activeTabGroup.activeTab?.input;
  return input instanceof vscode.TabInputText || input instanceof vscode.TabInputCustom
    ? input.uri.toString()
    : undefined;
}

function activeTabViewType(): string | undefined {
  const input = vscode.window.tabGroups.activeTabGroup.activeTab?.input;
  return input instanceof vscode.TabInputCustom ? input.viewType : undefined;
}

async function until(condition: () => boolean, what: string): Promise<void> {
  for (let i = 0; i < 100; i++) {
    if (condition()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  assert.fail(`timed out waiting for ${what}`);
}

const spec = () => file("spec/models/user_spec.rb");

async function read(uri: vscode.Uri): Promise<string> {
  return new TextDecoder().decode(await vscode.workspace.fs.readFile(uri));
}

/** Runs omoteura in the sample project, as the extension is set up to. */
function omoteura(...args: string[]): string {
  assert.ok(workspace);
  const [program, ...base] = vscode.workspace.getConfiguration("omoteura").get<string[]>("command") ?? [];
  assert.ok(program);
  return execFileSync(program, [...base, ...args, "--root", workspace.fsPath], {
    cwd: workspace.fsPath,
    encoding: "utf8",
  });
}

/** The drawing in a diagram file, as omoteura reads it. */
function scene(uri: vscode.Uri): { elements: { id: string; x?: number; strokeColor?: string; link?: string }[] } {
  return JSON.parse(omoteura("diagram", uri.fsPath)).scene;
}

describe("Omoteura", () => {
  before(async () => {
    const extension = vscode.extensions.getExtension<OmoteuraApi>("kaibyaku.omoteura");
    assert.ok(extension, "the extension should be installed");
    api = await extension.activate();
  });

  afterEach(async () => {
    await vscode.commands.executeCommand("workbench.action.closeAllEditors");
  });

  it("marks the lines the spec's diagram links to", async () => {
    const refreshed = refreshOf(spec());
    await show(spec());
    await refreshed;

    assert.equal(api.error(spec()), undefined);
    assert.equal(api.report(spec())?.attachment?.diagram_path, "ura/spec/models/user_spec.excalidraw.md");
    assert.deepEqual(
      api.markers(spec()).map((marker) => [marker.line + 1, marker.status]),
      [
        [7, "linked"],
        [12, "linked"],
      ],
    );
  });

  it("shows test results when the formatter writes them", async () => {
    await show(spec());
    const refreshed = refreshOf(spec(), () => api.markers(spec()).some((marker) => marker.status === "failed"));
    const example = (line: number, status: string, message: string | null = null) => ({
      id: `./spec/models/user_spec.rb[${line}]`,
      file_path: "spec/models/user_spec.rb",
      line_number: line,
      full_description: `User line ${line}`,
      status,
      message,
    });
    await vscode.workspace.fs.writeFile(
      file("tmp/omoteura/results.json"),
      new TextEncoder().encode(
        JSON.stringify({
          version: 1,
          examples: [
            example(8, "passed"),
            example(13, "passed"),
            example(18, "failed", 'expected: "aki@example.com"\n     got: "aki"'),
          ],
        }),
      ),
    );
    await refreshed;

    assert.deepEqual(
      api.markers(spec()).map((marker) => [marker.line + 1, marker.status]),
      [
        [7, "passed"],
        [12, "failed"],
      ],
    );
  });

  it("explains a marker on hover, failure message included", async () => {
    await show(spec());
    await until(() => api.markers(spec()).some((marker) => marker.status === "failed"), "the failing marker");

    const hovers = await vscode.commands.executeCommand<vscode.Hover[]>(
      "vscode.executeHoverProvider",
      spec(),
      new vscode.Position(11, 2),
    );
    const text = hovers
      .flatMap((hover) => hover.contents)
      .map((content) => (content instanceof vscode.MarkdownString ? content.value : String(content)))
      .join("\n");

    // appendText escapes spaces as &nbsp; so the diagram's text cannot become markdown.
    assert.match(text, /表示名(?: |&nbsp;)—(?: |&nbsp;)failing/);
    assert.match(text, /omoteura:#display_name/);
    assert.match(text, /got: "aki"/);
  });

  it("flips from the code to its diagram, drawn by Excalidraw, and back", async () => {
    const diagram = file("ura/spec/models/user_spec.excalidraw.md");
    await show(spec());
    await until(() => api.report(spec()) !== undefined, "the report");

    const rendered = new Promise<void>((resolve) => {
      const listener = api.onDidRenderDiagram((uri) => {
        if (uri.toString() === diagram.toString()) {
          listener.dispose();
          resolve();
        }
      });
    });
    await vscode.commands.executeCommand("omoteura.flip");
    await rendered;

    assert.equal(activeTabUri(), diagram.toString());
    assert.equal(activeTabViewType(), "omoteura.diagram");
    assert.equal(api.diagram(diagram)?.renderedElements, 5);
    assert.deepEqual(api.diagram(diagram)?.failures, []);
    assert.deepEqual(api.diagram(diagram)?.report?.attached_to, ["spec/models/user_spec.rb"]);

    await vscode.commands.executeCommand("omoteura.flip");
    await until(() => activeTabUri() === spec().toString(), "the spec tab");
  });

  it("renders a diagram drafted by omoteura draft", async () => {
    assert.ok(workspace);
    await vscode.workspace.fs.writeFile(
      file("app/models/comment.rb"),
      new TextEncoder().encode("class Comment\n  def body\n  end\n\n  def author\n  end\nend\n"),
    );
    const [program, ...args] = vscode.workspace.getConfiguration("omoteura").get<string[]>("command") ?? [];
    assert.ok(program);
    execFileSync(program, [...args, "draft", "app/models/comment.rb", "--root", workspace.fsPath], {
      cwd: workspace.fsPath,
    });
    const diagram = file("ura/app/models/comment.excalidraw");
    const drafted = JSON.parse(new TextDecoder().decode(await vscode.workspace.fs.readFile(diagram)));

    await vscode.commands.executeCommand("vscode.openWith", diagram, "omoteura.diagram");
    await until(() => api.diagram(diagram)?.renderedElements !== undefined, "the drafted diagram");

    assert.equal(api.diagram(diagram)?.renderedElements, drafted.elements.length);
    assert.deepEqual(api.diagram(diagram)?.failures, []);
    assert.deepEqual(
      api.diagram(diagram)?.report?.shapes.map((shape) => [shape.link, shape.target?.start_line]),
      [
        ["omoteura:#body", 2],
        ["omoteura:#author", 5],
      ],
    );
  });

  it("opens the code a shape links to and selects its lines", async () => {
    const diagram = file("ura/spec/models/user_spec.excalidraw.md");
    await vscode.commands.executeCommand("vscode.openWith", diagram, "omoteura.diagram");
    await until(() => api.diagram(diagram)?.report !== undefined, "the diagram report");

    await api.openShape(diagram, "required");

    await until(() => vscode.window.activeTextEditor?.document.uri.toString() === spec().toString(), "the spec");
    const selection = vscode.window.activeTextEditor?.selection;
    assert.deepEqual([selection?.start.line, selection?.end.line], [6, 8]);
  });

  it("explains once when omoteura cannot be run", async () => {
    const settings = vscode.workspace.getConfiguration("omoteura");
    const command = settings.get<string[]>("command");
    const warnings: string[] = [];
    const showWarningMessage = vscode.window.showWarningMessage;
    Object.assign(vscode.window, {
      showWarningMessage: async (message: string) => {
        warnings.push(message);
        return undefined;
      },
    });
    try {
      await settings.update("command", ["omoteura-missing-program"], vscode.ConfigurationTarget.Workspace);
      // The refresh the change triggers can still read the old setting on a
      // slow machine, so wait until it is visible and refresh explicitly.
      await until(
        () =>
          vscode.workspace.getConfiguration("omoteura", spec()).get<string[]>("command")?.[0] ===
          "omoteura-missing-program",
        "the new setting",
      );
      await show(spec());
      await vscode.commands.executeCommand("omoteura.refresh");
      await until(() => api.error(spec()) !== undefined, "the error");
      // A second failure of the same kind must not announce it again.
      const second = refreshOf(spec(), () => api.error(spec()) !== undefined);
      await vscode.commands.executeCommand("omoteura.refresh");
      await second;
    } finally {
      Object.assign(vscode.window, { showWarningMessage });
      await settings.update("command", command, vscode.ConfigurationTarget.Workspace);
    }

    assert.deepEqual(warnings, [
      "VS Code cannot find omoteura-missing-program. Start VS Code from a terminal so it sees your PATH, or set omoteura.command to a full path.",
    ]);
  });

  it("saves an edited Obsidian note in place, keeping the note and leaving test outlines out", async () => {
    await vscode.workspace.fs.writeFile(
      file("app/models/tag.rb"),
      new TextEncoder().encode("class Tag\n  def name\n  end\nend\n"),
    );
    omoteura("draft", "app/models/tag.rb", "--format", "md");
    const diagram = file("ura/app/models/tag.excalidraw.md");
    const drafted = await read(diagram);
    await vscode.workspace.fs.writeFile(
      diagram,
      new TextEncoder().encode(drafted.replace("# Excalidraw Data", "なぜタグを分けたか。\n\n# Excalidraw Data")),
    );

    await vscode.commands.executeCommand("vscode.openWith", diagram, "omoteura.diagram");
    await until(() => api.diagram(diagram)?.renderedElements !== undefined, "the note");
    const box = api.diagram(diagram)?.report?.shapes[0];
    assert.ok(box);
    const before = scene(diagram).elements.find((element) => element.id === box.id);
    api.editDiagram(diagram, box.id, { x: 640 });
    await until(() => api.diagram(diagram)?.dirty === true, "the change");

    assert.equal((await vscode.workspace.save(diagram))?.toString(), diagram.toString());

    assert.equal(api.diagram(diagram)?.dirty, false);
    const saved = await read(diagram);
    assert.match(saved, /なぜタグを分けたか。\n\n# Excalidraw Data\n/);
    assert.match(saved, /```compressed-json\n/);
    const after = scene(diagram).elements.find((element) => element.id === box.id);
    assert.equal(after?.x, 640);
    assert.equal(after?.strokeColor, before?.strokeColor);
    assert.equal(after?.link, "omoteura:#name");
  });

  it("does not save over a change made elsewhere, and reverts to it", async () => {
    await vscode.workspace.fs.writeFile(
      file("app/models/badge.rb"),
      new TextEncoder().encode("class Badge\n  def name\n  end\nend\n"),
    );
    omoteura("draft", "app/models/badge.rb");
    const diagram = file("ura/app/models/badge.excalidraw");
    await vscode.commands.executeCommand("vscode.openWith", diagram, "omoteura.diagram");
    await until(() => api.diagram(diagram)?.renderedElements !== undefined, "the diagram");
    const [box] = api.diagram(diagram)?.report?.shapes ?? [];
    assert.ok(box);
    api.editDiagram(diagram, box.id, { x: 640 });
    await until(() => api.diagram(diagram)?.dirty === true, "the change");

    const elsewhere = JSON.parse(await read(diagram));
    elsewhere.elements = [];
    await vscode.workspace.fs.writeFile(diagram, new TextEncoder().encode(JSON.stringify(elsewhere)));

    await assert.rejects(Promise.resolve(vscode.workspace.save(diagram)), /changed on disk since it was opened/);
    assert.deepEqual(JSON.parse(await read(diagram)).elements, []);
    assert.equal(api.diagram(diagram)?.dirty, true);

    await vscode.commands.executeCommand("workbench.action.files.revert");
    await until(() => api.diagram(diagram)?.renderedElements === 0, "the reverted diagram");
    assert.equal(api.diagram(diagram)?.dirty, false);
  });

  it("creates an empty diagram at the conventional path when asked", async () => {
    const code = file("app/models/post.rb");
    await vscode.workspace.fs.writeFile(code, new TextEncoder().encode("class Post\nend\n"));
    await show(code);
    await until(() => api.report(code) !== undefined, "the report");

    const showInformationMessage = vscode.window.showInformationMessage;
    Object.assign(vscode.window, { showInformationMessage: async () => "Create" });
    try {
      await vscode.commands.executeCommand("omoteura.flip");
    } finally {
      Object.assign(vscode.window, { showInformationMessage });
    }

    const diagram = file("ura/app/models/post.excalidraw");
    await until(() => activeTabUri() === diagram.toString(), "the new diagram tab");
    const created = JSON.parse(new TextDecoder().decode(await vscode.workspace.fs.readFile(diagram)));
    assert.equal(created.type, "excalidraw");
    assert.deepEqual(created.elements, []);
  });
});
