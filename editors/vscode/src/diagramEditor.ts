import { randomBytes } from "node:crypto";
import * as vscode from "vscode";
import { type DiagramReport, InspectError, inspectDiagram, linkCandidates, saveDiagram } from "./inspect.ts";
import type { HostMessage, Scene, WebviewMessage } from "./messages.ts";
import { decorate, targetOf, undecorate } from "./overlay.ts";

export const DIAGRAM_VIEW_TYPE = "omoteura.diagram";

/** What a diagram view has shown, for the integration tests. */
export interface DiagramViewState {
  revision: number;
  /** Elements Excalidraw rendered for the current revision, once it has. */
  renderedElements: number | undefined;
  report: DiagramReport | undefined;
  failures: string[];
  /** True from the first change until the drawing is saved or reverted. */
  dirty: boolean;
}

/** What a backup holds: the unsaved drawing and the file version it was based on. */
interface Backup {
  digest: string | null;
  scene: Scene;
}

/** A drawing open in VS Code. Its unsaved state lives in the webview. */
class DiagramDocument implements vscode.CustomDocument {
  /** The file as last read or written, so a save never overwrites a change made elsewhere. */
  digest: string | null = null;
  /** An unsaved drawing restored after VS Code restarted, shown once instead of the file. */
  restored: Backup | undefined;

  readonly uri: vscode.Uri;

  constructor(uri: vscode.Uri) {
    this.uri = uri;
  }

  dispose(): void {}
}

interface View extends DiagramViewState {
  document: DiagramDocument;
  panel: vscode.WebviewPanel;
  disposed: boolean;
  /** Counts loads, so one overtaken by a later load is dropped. */
  loads: number;
  /** The scene last loaded, as read and as shown with outlines, to take the outlines out on saving. */
  shown: { original: Scene; decorated: Scene } | undefined;
}

const ANSWER_TIMEOUT_MS = 10_000;

/**
 * Shows and edits a drawing with Excalidraw, linked shapes outlined by test
 * status. Saving goes through `omoteura save`, which writes the file's own
 * format, Obsidian notes included.
 */
export class DiagramEditorProvider implements vscode.CustomEditorProvider<DiagramDocument> {
  readonly #extensionUri: vscode.Uri;
  readonly #command: (uri: vscode.Uri) => string[];
  readonly #log: vscode.LogOutputChannel;
  readonly #views = new Set<View>();
  readonly #rendered = new vscode.EventEmitter<vscode.Uri>();
  readonly #changed = new vscode.EventEmitter<vscode.CustomDocumentContentChangeEvent<DiagramDocument>>();
  // Questions to a webview, answered by a message with the same requestId.
  readonly #requests = new Map<number, (answer: WebviewMessage) => void>();
  #nextRequest = 0;

  readonly onDidRender = this.#rendered.event;
  readonly onDidChangeCustomDocument = this.#changed.event;

  constructor(extensionUri: vscode.Uri, command: (uri: vscode.Uri) => string[], log: vscode.LogOutputChannel) {
    this.#extensionUri = extensionUri;
    this.#command = command;
    this.#log = log;
  }

  async openCustomDocument(uri: vscode.Uri, context: vscode.CustomDocumentOpenContext): Promise<DiagramDocument> {
    const document = new DiagramDocument(uri);
    if (context.backupId) {
      try {
        const data = await vscode.workspace.fs.readFile(vscode.Uri.parse(context.backupId));
        document.restored = JSON.parse(new TextDecoder().decode(data)) as Backup;
      } catch (error) {
        this.#log.warn(
          `Could not restore unsaved changes to ${vscode.workspace.asRelativePath(uri)}: ${String(error)}`,
        );
      }
    }
    return document;
  }

  resolveCustomEditor(document: DiagramDocument, panel: vscode.WebviewPanel): void {
    const assets = vscode.Uri.joinPath(this.#extensionUri, "dist", "webview");
    panel.webview.options = { enableScripts: true, localResourceRoots: [assets] };
    panel.webview.html = html(panel.webview, assets);

    const view: View = {
      document,
      panel,
      revision: 0,
      renderedElements: undefined,
      report: undefined,
      failures: [],
      dirty: false,
      shown: undefined,
      disposed: false,
      loads: 0,
    };
    this.#views.add(view);
    panel.onDidDispose(() => {
      view.disposed = true;
      this.#views.delete(view);
    });
    panel.webview.onDidReceiveMessage((message: WebviewMessage) => this.#receive(view, message));
  }

  async saveCustomDocument(document: DiagramDocument): Promise<void> {
    await this.#write(document, document.uri);
  }

  async saveCustomDocumentAs(document: DiagramDocument, destination: vscode.Uri): Promise<void> {
    await this.#write(document, destination);
  }

  async revertCustomDocument(document: DiagramDocument): Promise<void> {
    const view = this.#viewOf(document);
    document.restored = undefined;
    if (view) {
      view.dirty = false;
      await this.#load(view);
    }
  }

  async backupCustomDocument(
    document: DiagramDocument,
    context: vscode.CustomDocumentBackupContext,
  ): Promise<vscode.CustomDocumentBackup> {
    const view = this.#viewOf(document);
    if (view) {
      const { drawing } = await this.#drawing(view);
      const backup: Backup = { digest: document.digest, scene: JSON.parse(drawing) as Scene };
      await vscode.workspace.fs.writeFile(context.destination, new TextEncoder().encode(JSON.stringify(backup)));
    }
    return {
      id: context.destination.toString(),
      delete: () => void vscode.workspace.fs.delete(context.destination).then(undefined, () => {}),
    };
  }

  /** The current state of the view showing uri, if one is open. */
  state(uri: vscode.Uri): DiagramViewState | undefined {
    return this.#viewOfUri(uri);
  }

  /** Opens the code behind a shape, as clicking its link in the drawing does. */
  async openShape(uri: vscode.Uri, elementId: string): Promise<void> {
    const view = this.#viewOfUri(uri);
    if (view) {
      await this.#openLink(view, elementId);
    }
  }

  /**
   * Links a shape to code chosen from the places in the code file the
   * diagram is attached to: the shape given, or else the one selected in
   * the active diagram view. The change is unsaved, like any other edit.
   */
  async linkShape(uri?: vscode.Uri, elementId?: string): Promise<void> {
    const view = uri ? this.#viewOfUri(uri) : [...this.#views].find((v) => v.panel.active);
    if (!view) {
      void vscode.window.showInformationMessage("Open a diagram to link one of its shapes to code.");
      return;
    }
    let shape: { id: string; link: string | null } | undefined;
    if (elementId) {
      shape = { id: elementId, link: null };
    } else {
      const answer = await this.#ask(view, "selection");
      const selected = answer.type === "selected" ? answer.elements : [];
      if (selected.length !== 1) {
        void vscode.window.showInformationMessage("Select one shape to link it to code.");
        return;
      }
      shape = selected[0];
    }
    const folder = vscode.workspace.getWorkspaceFolder(view.document.uri);
    const codePath = view.report?.attached_to[0];
    if (!folder || !shape || !codePath) {
      void vscode.window.showWarningMessage(
        "This diagram is not attached to any code. Attach it by its path under the diagrams folder, a magic comment or .omoteura.yml.",
      );
      return;
    }
    let candidates: Awaited<ReturnType<typeof linkCandidates>>;
    try {
      candidates = await linkCandidates(
        this.#command(view.document.uri),
        folder.uri.fsPath,
        vscode.Uri.joinPath(folder.uri, codePath).fsPath,
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      void vscode.window.showErrorMessage(`Omoteura could not list the places in ${codePath}: ${message}`);
      return;
    }
    const current = shape.link;
    const items: (vscode.QuickPickItem & { link: string | null })[] = candidates.map((candidate) => ({
      label: candidate.label,
      description: `${candidate.kind} · line ${candidate.line}`,
      detail: candidate.link === current ? `${candidate.link} (current)` : candidate.link,
      link: candidate.link,
    }));
    if (current) {
      items.push({ label: "Remove the Link", description: current, link: null });
    }
    const pick = await vscode.window.showQuickPick(items, {
      placeHolder: `Link the shape to a place in ${codePath}`,
      matchOnDescription: true,
      matchOnDetail: true,
    });
    if (pick) {
      this.#post(view, { type: "edit", elementId: shape.id, changes: { link: pick.link } });
    }
  }

  /** Changes one element in the view showing uri as the user would, for the integration tests. */
  edit(uri: vscode.Uri, elementId: string, changes: Record<string, unknown>): void {
    const view = this.#viewOfUri(uri);
    if (view) {
      this.#post(view, { type: "edit", elementId, changes });
    }
  }

  /** Reloads every open view, after code, diagrams or test results changed. */
  refreshAll(): void {
    for (const view of this.#views) {
      void this.#load(view);
    }
  }

  dispose(): void {
    this.#rendered.dispose();
    this.#changed.dispose();
  }

  #viewOf(document: DiagramDocument): View | undefined {
    return [...this.#views].find((view) => view.document === document);
  }

  #viewOfUri(uri: vscode.Uri): View | undefined {
    return [...this.#views].find((view) => view.document.uri.toString() === uri.toString());
  }

  async #receive(view: View, message: WebviewMessage): Promise<void> {
    switch (message.type) {
      case "ready":
        await this.#load(view);
        break;
      case "rendered":
        if (message.revision === view.revision) {
          view.renderedElements = message.elementCount;
          this.#rendered.fire(view.document.uri);
        }
        break;
      case "changed":
        view.dirty = true;
        this.#changed.fire({ document: view.document });
        break;
      case "serialized":
      case "selected":
        this.#requests.get(message.requestId)?.(message);
        this.#requests.delete(message.requestId);
        break;
      case "openLink":
        await this.#openLink(view, message.elementId);
        break;
      case "failed":
        view.failures.push(message.message);
        this.#log.error(
          `The diagram view for ${vscode.workspace.asRelativePath(view.document.uri)} failed: ${message.message}`,
        );
        break;
    }
  }

  async #load(view: View): Promise<void> {
    const { document } = view;
    const folder = vscode.workspace.getWorkspaceFolder(document.uri);
    if (!folder) {
      this.#post(view, { type: "error", message: "Omoteura shows diagrams that are inside a workspace folder." });
      return;
    }
    const load = ++view.loads;
    try {
      const report = await inspectDiagram(this.#command(document.uri), folder.uri.fsPath, document.uri.fsPath);
      if (load !== view.loads) {
        return;
      }
      view.report = report;
      // Unsaved changes stay; the links and statuses still follow the file.
      if (view.dirty) {
        return;
      }
      if (report.error || !report.scene) {
        this.#post(view, { type: "error", message: report.error ?? "This file is not an Excalidraw drawing." });
        return;
      }
      const restored = document.restored;
      document.restored = undefined;
      document.digest = restored ? restored.digest : report.digest;
      view.dirty = restored !== undefined;
      const original = restored?.scene ?? report.scene;
      const decorated = decorate(original, report.shapes);
      view.shown = { original, decorated };
      view.revision += 1;
      view.renderedElements = undefined;
      this.#post(view, { type: "load", revision: view.revision, scene: decorated });
    } catch (error) {
      if (load !== view.loads) {
        return;
      }
      const message = error instanceof InspectError || error instanceof Error ? error.message : String(error);
      this.#log.error(`Could not read ${vscode.workspace.asRelativePath(document.uri)}: ${message}`);
      this.#post(view, { type: "error", message: `Omoteura could not read this diagram: ${message}` });
    }
  }

  /** The drawing as Excalidraw saves it, without the status outlines. */
  async #drawing(view: View): Promise<{ drawing: string; signature: string }> {
    const answer = await this.#ask(view, "serialize");
    if (answer.type !== "serialized") {
      throw new Error("The diagram view answered with something other than the drawing.");
    }
    if (!view.shown) {
      return answer;
    }
    const edited = JSON.parse(answer.drawing) as Scene;
    const drawing = undecorate(edited, view.shown.original, view.shown.decorated);
    return { drawing: JSON.stringify(drawing), signature: answer.signature };
  }

  /** Sends the webview a question and resolves with its answer. */
  #ask(view: View, type: "serialize" | "selection"): Promise<WebviewMessage> {
    return new Promise((resolve, reject) => {
      const requestId = ++this.#nextRequest;
      const timer = setTimeout(() => {
        this.#requests.delete(requestId);
        reject(new Error("The diagram view did not answer in time."));
      }, ANSWER_TIMEOUT_MS);
      this.#requests.set(requestId, (answer) => {
        clearTimeout(timer);
        resolve(answer);
      });
      this.#post(view, { type, requestId });
    });
  }

  async #write(document: DiagramDocument, destination: vscode.Uri): Promise<void> {
    const view = this.#viewOf(document);
    const folder = vscode.workspace.getWorkspaceFolder(destination);
    if (!view) {
      throw new Error("Omoteura saves a diagram only while it is open.");
    }
    if (!folder) {
      throw new Error("Omoteura saves diagrams inside a workspace folder.");
    }
    const sameFile = destination.toString() === document.uri.toString();
    const { drawing, signature } = await this.#drawing(view);
    const result = await saveDiagram(
      this.#command(destination),
      folder.uri.fsPath,
      destination.fsPath,
      drawing,
      sameFile ? document.digest : null,
    );
    if (result.error) {
      const name = vscode.workspace.asRelativePath(destination);
      throw new Error(
        result.conflict
          ? `${name} changed on disk since it was opened. Revert the diagram to see the change, or save yours under another name.`
          : `Omoteura could not save ${name}: ${result.error}`,
      );
    }
    if (sameFile) {
      document.digest = result.digest;
    }
    view.dirty = false;
    this.#post(view, { type: "saved", signature });
  }

  async #openLink(view: View, elementId: string): Promise<void> {
    const folder = vscode.workspace.getWorkspaceFolder(view.document.uri);
    const shapes = view.report?.shapes ?? [];
    const target = targetOf(shapes, elementId);
    if (!folder || !target) {
      const reason = shapes.find((shape) => shape.id === elementId)?.error;
      void vscode.window.showWarningMessage(reason ?? "This shape's link does not point to any code.");
      return;
    }
    const lines = new vscode.Range(target.start_line - 1, 0, target.end_line - 1, 0);
    await vscode.window.showTextDocument(vscode.Uri.joinPath(folder.uri, target.path), {
      selection: lines,
      viewColumn: vscode.ViewColumn.Beside,
    });
  }

  // A load or save still running when its editor closes has nothing to tell.
  #post(view: View, message: HostMessage): void {
    if (!view.disposed) {
      void view.panel.webview.postMessage(message);
    }
  }
}

function html(webview: vscode.Webview, assets: vscode.Uri): string {
  const nonce = randomBytes(16).toString("base64");
  const source = webview.cspSource;
  const asset = (name: string) => webview.asWebviewUri(vscode.Uri.joinPath(assets, name)).toString();
  // Excalidraw sets inline styles and loads its fonts from the asset path;
  // nothing may come from outside the extension's dist/webview.
  const csp = [
    "default-src 'none'",
    `script-src 'nonce-${nonce}'`,
    `style-src ${source} 'unsafe-inline'`,
    `font-src ${source}`,
    `img-src ${source} data: blob:`,
    `connect-src ${source}`,
    "worker-src blob:",
  ].join("; ");
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="${csp}">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="${asset("main.css")}">
<style>
html, body, #root { height: 100%; margin: 0; padding: 0; }
.omoteura-error { position: absolute; z-index: 10; margin: 16px; padding: 8px 12px; font-family: var(--vscode-font-family); color: var(--vscode-errorForeground); background: var(--vscode-editor-background); border: 1px solid var(--vscode-errorForeground); }
</style>
</head>
<body>
<div id="root"></div>
<script nonce="${nonce}">window.EXCALIDRAW_ASSET_PATH = ${JSON.stringify(`${asset("")}/`)}; window.EXCALIDRAW_EXPORT_SOURCE = "https://github.com/kaibyaku-jp/omoteura";</script>
<script nonce="${nonce}" src="${asset("main.js")}"></script>
</body>
</html>`;
}
