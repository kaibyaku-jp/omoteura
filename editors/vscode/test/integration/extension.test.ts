import assert from "node:assert/strict";
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
  return input instanceof vscode.TabInputText ? input.uri.toString() : undefined;
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

  it("flips from the code to its diagram and back", async () => {
    await show(spec());
    await until(() => api.report(spec()) !== undefined, "the report");

    await vscode.commands.executeCommand("omoteura.flip");
    await until(() => activeTabUri() === file("ura/spec/models/user_spec.excalidraw.md").toString(), "the diagram tab");

    await vscode.commands.executeCommand("omoteura.flip");
    await until(() => activeTabUri() === spec().toString(), "the spec tab");
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
