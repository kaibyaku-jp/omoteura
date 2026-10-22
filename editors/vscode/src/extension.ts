import * as vscode from "vscode";
import { InspectError, inspect, type Report } from "./inspect.ts";
import {
  hoverEntries,
  MARKER_STATUSES,
  type Marker,
  type MarkerStatus,
  markersFor,
  STATUS_WORDS,
  summarize,
  summaryText,
} from "./markers.ts";
import { diagnose, type SetupProblem } from "./setup.ts";

const DEFAULT_COMMAND = ["bundle", "exec", "omoteura"];
const REFRESH_DELAY_MS = 250;

const RULER_COLORS: Record<MarkerStatus, string> = {
  failed: "#E8590C",
  broken: "#8A8F98",
  pending: "#E0A526",
  passed: "#2A9D8F",
  linked: "#8A8F98",
};

const STATUS_ICONS: Record<MarkerStatus, string> = {
  failed: "$(error)",
  broken: "$(debug-disconnect)",
  pending: "$(clock)",
  passed: "$(pass)",
  linked: "$(link)",
};

const EMPTY_DIAGRAM = `${JSON.stringify(
  {
    type: "excalidraw",
    version: 2,
    source: "https://github.com/kaibyaku-jp/omoteura",
    elements: [],
    appState: { viewBackgroundColor: "#ffffff" },
    files: {},
  },
  null,
  2,
)}\n`;

/** Returned from activate for the integration tests. */
export interface OmoteuraApi {
  report(uri: vscode.Uri): Report | undefined;
  markers(uri: vscode.Uri): readonly Marker[];
  /** Why the last inspection of uri failed, if it did. */
  error(uri: vscode.Uri): string | undefined;
  readonly onDidRefresh: vscode.Event<vscode.Uri>;
}

export function activate(context: vscode.ExtensionContext): OmoteuraApi {
  const log = vscode.window.createOutputChannel("Omoteura", { log: true });
  const reports = new Map<string, Report>();
  const errors = new Map<string, string>();
  // Each setup problem is announced once a session, not for every file.
  const announced = new Set<SetupProblem>();
  const timers = new Map<string, ReturnType<typeof setTimeout>>();
  const refreshed = new vscode.EventEmitter<vscode.Uri>();

  const decorations = new Map(
    MARKER_STATUSES.map((status) => [
      status,
      vscode.window.createTextEditorDecorationType({
        gutterIconPath: context.asAbsolutePath(`media/gutter-${status}.svg`),
        gutterIconSize: "contain",
        overviewRulerColor: RULER_COLORS[status],
        overviewRulerLane: vscode.OverviewRulerLane.Left,
      }),
    ]),
  );

  const statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 50);
  statusBar.command = "omoteura.flip";

  function isCode(document: vscode.TextDocument): boolean {
    return document.languageId === "ruby" && document.uri.scheme === "file";
  }

  async function refresh(document: vscode.TextDocument): Promise<void> {
    const folder = vscode.workspace.getWorkspaceFolder(document.uri);
    if (!folder || !isCode(document)) {
      return;
    }
    const command = vscode.workspace
      .getConfiguration("omoteura", document.uri)
      .get<string[]>("command", DEFAULT_COMMAND);
    const key = document.uri.toString();
    try {
      reports.set(key, await inspect(command, folder.uri.fsPath, document.uri.fsPath));
      errors.delete(key);
    } catch (error) {
      const message = error instanceof InspectError || error instanceof Error ? error.message : String(error);
      reports.delete(key);
      errors.set(key, message);
      log.error(`Could not inspect ${vscode.workspace.asRelativePath(document.uri)}: ${message}`);
      announce(message);
    }
    render();
    refreshed.fire(document.uri);
  }

  function announce(error: string): void {
    const diagnosis = diagnose(error);
    if (!diagnosis || announced.has(diagnosis.problem)) {
      return;
    }
    announced.add(diagnosis.problem);
    const openSettings = "Open Settings";
    const showOutput = "Show Output";
    void vscode.window.showWarningMessage(diagnosis.message, openSettings, showOutput).then((choice) => {
      if (choice === openSettings) {
        void vscode.commands.executeCommand("workbench.action.openSettings", "omoteura.command");
      } else if (choice === showOutput) {
        log.show();
      }
    });
  }

  function scheduleRefresh(document: vscode.TextDocument): void {
    if (!isCode(document)) {
      return;
    }
    const key = document.uri.toString();
    clearTimeout(timers.get(key));
    timers.set(
      key,
      setTimeout(() => {
        timers.delete(key);
        void refresh(document);
      }, REFRESH_DELAY_MS),
    );
  }

  function refreshVisible(): void {
    for (const editor of vscode.window.visibleTextEditors) {
      scheduleRefresh(editor.document);
    }
  }

  function render(): void {
    for (const editor of vscode.window.visibleTextEditors) {
      const report = reports.get(editor.document.uri.toString());
      const markers = report ? markersFor(report) : [];
      for (const [status, decoration] of decorations) {
        const lines = markers.filter((marker) => marker.status === status).map((marker) => marker.line);
        editor.setDecorations(
          decoration,
          lines.map((line) => new vscode.Range(line, 0, line, 0)),
        );
      }
    }
    renderStatusBar();
  }

  function renderStatusBar(): void {
    const document = vscode.window.activeTextEditor?.document;
    const error = document && errors.get(document.uri.toString());
    if (error) {
      statusBar.text = "$(warning) omoteura";
      statusBar.tooltip = diagnose(error)?.message ?? `Omoteura could not inspect this file: ${error}`;
      statusBar.show();
      return;
    }
    const report = document && reports.get(document.uri.toString());
    if (!report?.attachment) {
      statusBar.hide();
      return;
    }
    const summary = summarize(report);
    const worst = MARKER_STATUSES.find((status) => summary[status] > 0) ?? "linked";
    statusBar.text = `${STATUS_ICONS[worst]} omoteura`;
    statusBar.tooltip = `${report.attachment.diagram_path}: ${summaryText(summary)}. Click to flip to the diagram.`;
    statusBar.show();
  }

  function provideHover(document: vscode.TextDocument, position: vscode.Position): vscode.Hover | undefined {
    const report = reports.get(document.uri.toString());
    const marker = report && markersFor(report).find((m) => m.line === position.line);
    if (!marker) {
      return undefined;
    }
    // Diagram text goes in as plain text and code blocks, never as markdown.
    const markdown = new vscode.MarkdownString();
    for (const entry of hoverEntries(marker)) {
      markdown.appendMarkdown(`${STATUS_ICONS[entry.status]} `);
      markdown.appendText(`${entry.title} — ${STATUS_WORDS[entry.status]}`);
      markdown.appendCodeblock(entry.link, "text");
      for (const message of entry.messages) {
        markdown.appendCodeblock(message, "text");
      }
    }
    markdown.supportThemeIcons = true;
    return new vscode.Hover(markdown, new vscode.Range(marker.line, 0, marker.line, 0));
  }

  async function flip(): Promise<void> {
    const uri = activeUri();
    if (!uri) {
      return;
    }
    const document = vscode.workspace.textDocuments.find((d) => d.uri.toString() === uri.toString());
    if (document && isCode(document)) {
      await flipToDiagram(document);
    } else {
      await flipToCode(uri);
    }
  }

  async function flipToDiagram(document: vscode.TextDocument): Promise<void> {
    const folder = vscode.workspace.getWorkspaceFolder(document.uri);
    if (!folder) {
      return;
    }
    await refresh(document);
    const report = reports.get(document.uri.toString());
    if (!report) {
      void vscode.window.showErrorMessage("Omoteura could not inspect this file. See the Omoteura output for details.");
      return;
    }
    if (report.attachment?.missing) {
      void vscode.window.showWarningMessage(
        `${report.code_path} attaches ${report.attachment.diagram_path}, which does not exist.`,
      );
      return;
    }
    if (report.attachment) {
      await open(vscode.Uri.joinPath(folder.uri, report.attachment.diagram_path));
      return;
    }
    const create = "Create";
    const answer = await vscode.window.showInformationMessage(
      `There is no diagram behind ${report.code_path}. Create ${report.new_diagram_path}?`,
      create,
    );
    if (answer === create) {
      const diagram = vscode.Uri.joinPath(folder.uri, report.new_diagram_path);
      if (!(await exists(diagram))) {
        await vscode.workspace.fs.createDirectory(vscode.Uri.joinPath(diagram, ".."));
        await vscode.workspace.fs.writeFile(diagram, new TextEncoder().encode(EMPTY_DIAGRAM));
      }
      await open(diagram);
      scheduleRefresh(document);
    }
  }

  // A diagram can back several files; go to the one whose report names it.
  async function flipToCode(diagram: vscode.Uri): Promise<void> {
    const relative = vscode.workspace.asRelativePath(diagram, false);
    for (const [key, report] of reports) {
      if (report.attachment?.diagram_path === relative) {
        await open(vscode.Uri.parse(key));
        return;
      }
    }
    void vscode.window.showInformationMessage(
      "Omoteura does not know which code this diagram is behind yet. Open the code file and flip from there.",
    );
  }

  async function open(uri: vscode.Uri): Promise<void> {
    await vscode.commands.executeCommand("vscode.open", uri, { viewColumn: vscode.ViewColumn.Active });
  }

  context.subscriptions.push(
    log,
    refreshed,
    statusBar,
    ...decorations.values(),
    vscode.commands.registerCommand("omoteura.flip", flip),
    vscode.commands.registerCommand("omoteura.refresh", refreshVisible),
    vscode.languages.registerHoverProvider({ language: "ruby", scheme: "file" }, { provideHover }),
    vscode.window.onDidChangeVisibleTextEditors(() => {
      render();
      refreshVisible();
    }),
    vscode.window.onDidChangeActiveTextEditor(renderStatusBar),
    vscode.workspace.onDidSaveTextDocument(scheduleRefresh),
    vscode.workspace.onDidCloseTextDocument((document) => {
      reports.delete(document.uri.toString());
      errors.delete(document.uri.toString());
    }),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("omoteura")) {
        refreshVisible();
      }
    }),
    {
      dispose: () => {
        for (const timer of timers.values()) {
          clearTimeout(timer);
        }
      },
    },
  );

  // Test results, diagrams and settings all change what the markers show.
  for (const pattern of ["**/tmp/omoteura/results.json", "**/*.{excalidraw,md}", "**/.omoteura{,.local}.yml"]) {
    const watcher = vscode.workspace.createFileSystemWatcher(pattern);
    watcher.onDidChange(refreshVisible);
    watcher.onDidCreate(refreshVisible);
    watcher.onDidDelete(refreshVisible);
    context.subscriptions.push(watcher);
  }

  refreshVisible();

  return {
    report: (uri) => reports.get(uri.toString()),
    markers: (uri) => {
      const report = reports.get(uri.toString());
      return report ? markersFor(report) : [];
    },
    error: (uri) => errors.get(uri.toString()),
    onDidRefresh: refreshed.event,
  };
}

async function exists(uri: vscode.Uri): Promise<boolean> {
  try {
    await vscode.workspace.fs.stat(uri);
    return true;
  } catch {
    return false;
  }
}

/** The file in the active tab, whether a text editor or a custom editor shows it. */
function activeUri(): vscode.Uri | undefined {
  const input = vscode.window.tabGroups.activeTabGroup.activeTab?.input;
  if (input instanceof vscode.TabInputText || input instanceof vscode.TabInputCustom) {
    return input.uri;
  }
  return vscode.window.activeTextEditor?.document.uri;
}

export function deactivate(): void {}
