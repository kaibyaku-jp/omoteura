import { randomBytes } from "node:crypto";
import * as vscode from "vscode";
import { type DiagramReport, InspectError, inspectDiagram } from "./inspect.ts";
import type { HostMessage, WebviewMessage } from "./messages.ts";
import { decorate, targetOf } from "./overlay.ts";

export const DIAGRAM_VIEW_TYPE = "omoteura.diagram";

/** What a diagram view has shown, for the integration tests. */
export interface DiagramViewState {
  revision: number;
  /** Elements Excalidraw rendered for the current revision, once it has. */
  renderedElements: number | undefined;
  report: DiagramReport | undefined;
  failures: string[];
}

interface View extends DiagramViewState {
  uri: vscode.Uri;
  panel: vscode.WebviewPanel;
}

/** Shows a drawing read-only with Excalidraw, linked shapes outlined by test status. */
export class DiagramEditorProvider implements vscode.CustomReadonlyEditorProvider {
  readonly #extensionUri: vscode.Uri;
  readonly #command: (uri: vscode.Uri) => string[];
  readonly #log: vscode.LogOutputChannel;
  readonly #views = new Set<View>();
  readonly #rendered = new vscode.EventEmitter<vscode.Uri>();

  readonly onDidRender = this.#rendered.event;

  constructor(extensionUri: vscode.Uri, command: (uri: vscode.Uri) => string[], log: vscode.LogOutputChannel) {
    this.#extensionUri = extensionUri;
    this.#command = command;
    this.#log = log;
  }

  openCustomDocument(uri: vscode.Uri): vscode.CustomDocument {
    return { uri, dispose: () => {} };
  }

  resolveCustomEditor(document: vscode.CustomDocument, panel: vscode.WebviewPanel): void {
    const assets = vscode.Uri.joinPath(this.#extensionUri, "dist", "webview");
    panel.webview.options = { enableScripts: true, localResourceRoots: [assets] };
    panel.webview.html = html(panel.webview, assets);

    const view: View = {
      uri: document.uri,
      panel,
      revision: 0,
      renderedElements: undefined,
      report: undefined,
      failures: [],
    };
    this.#views.add(view);
    panel.onDidDispose(() => this.#views.delete(view));
    panel.webview.onDidReceiveMessage((message: WebviewMessage) => this.#receive(view, message));
  }

  /** The current state of the view showing uri, if one is open. */
  state(uri: vscode.Uri): DiagramViewState | undefined {
    return [...this.#views].find((view) => view.uri.toString() === uri.toString());
  }

  /** Opens the code behind a shape, as clicking its link in the drawing does. */
  async openShape(uri: vscode.Uri, elementId: string): Promise<void> {
    const view = [...this.#views].find((v) => v.uri.toString() === uri.toString());
    if (view) {
      await this.#openLink(view, elementId);
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
  }

  async #receive(view: View, message: WebviewMessage): Promise<void> {
    switch (message.type) {
      case "ready":
        await this.#load(view);
        break;
      case "rendered":
        if (message.revision === view.revision) {
          view.renderedElements = message.elementCount;
          this.#rendered.fire(view.uri);
        }
        break;
      case "openLink":
        await this.#openLink(view, message.elementId);
        break;
      case "failed":
        view.failures.push(message.message);
        this.#log.error(`The diagram view for ${vscode.workspace.asRelativePath(view.uri)} failed: ${message.message}`);
        break;
    }
  }

  async #load(view: View): Promise<void> {
    const folder = vscode.workspace.getWorkspaceFolder(view.uri);
    if (!folder) {
      this.#post(view, { type: "error", message: "Omoteura shows diagrams that are inside a workspace folder." });
      return;
    }
    try {
      const report = await inspectDiagram(this.#command(view.uri), folder.uri.fsPath, view.uri.fsPath);
      view.report = report;
      if (report.error || !report.scene) {
        this.#post(view, { type: "error", message: report.error ?? "This file is not an Excalidraw drawing." });
        return;
      }
      view.revision += 1;
      view.renderedElements = undefined;
      this.#post(view, { type: "load", revision: view.revision, scene: decorate(report.scene, report.shapes) });
    } catch (error) {
      const message = error instanceof InspectError || error instanceof Error ? error.message : String(error);
      this.#log.error(`Could not read ${vscode.workspace.asRelativePath(view.uri)}: ${message}`);
      this.#post(view, { type: "error", message: `Omoteura could not read this diagram: ${message}` });
    }
  }

  async #openLink(view: View, elementId: string): Promise<void> {
    const folder = vscode.workspace.getWorkspaceFolder(view.uri);
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

  #post(view: View, message: HostMessage): void {
    void view.panel.webview.postMessage(message);
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
<script nonce="${nonce}">window.EXCALIDRAW_ASSET_PATH = ${JSON.stringify(`${asset("")}/`)};</script>
<script nonce="${nonce}" src="${asset("main.js")}"></script>
</body>
</html>`;
}
