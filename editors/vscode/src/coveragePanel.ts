import * as vscode from "vscode";
import {
  type CoverageGroup,
  type CoverageStatus,
  coverageDescription,
  coverageGroups,
  coverageMessage,
  coverageStatus,
} from "./coverage.ts";
import {
  type CoverageItem,
  type CoverageReport,
  type CoveredExample,
  InspectError,
  inspectCoverage,
} from "./inspect.ts";

export const COVERAGE_VIEW_ID = "omoteura.coverage";

type Node =
  | { type: "group"; group: CoverageGroup }
  | { type: "item"; item: CoverageItem }
  | { type: "example"; example: CoveredExample };

const ICONS: Record<CoverageStatus, vscode.ThemeIcon> = {
  failing: new vscode.ThemeIcon("error", new vscode.ThemeColor("testing.iconFailed")),
  covered: new vscode.ThemeIcon("pass", new vscode.ThemeColor("testing.iconPassed")),
  ran: new vscode.ThemeIcon("check", new vscode.ThemeColor("testing.iconPassed")),
  untested: new vscode.ThemeIcon("circle-large-outline", new vscode.ThemeColor("testing.iconQueued")),
};

/**
 * The coverage panel: which declarations and public methods of the active
 * Ruby file its specs cover. Separate from diagrams; it lists any file.
 */
export class CoveragePanel implements vscode.TreeDataProvider<Node>, vscode.Disposable {
  readonly #command: (uri: vscode.Uri) => string[];
  readonly #log: vscode.LogOutputChannel;
  readonly #changed = new vscode.EventEmitter<Node | undefined>();
  readonly #refreshed = new vscode.EventEmitter<vscode.Uri>();
  readonly #view: vscode.TreeView<Node>;
  #uri: vscode.Uri | undefined;
  #report: CoverageReport | undefined;
  #folder: vscode.Uri | undefined;
  // Only the latest request is shown; an older one finishing later is stale.
  #requests = 0;

  readonly onDidChangeTreeData = this.#changed.event;
  /** Fires with the file the panel shows, each time it has been brought up to date. */
  readonly onDidRefresh = this.#refreshed.event;

  constructor(command: (uri: vscode.Uri) => string[], log: vscode.LogOutputChannel) {
    this.#command = command;
    this.#log = log;
    this.#view = vscode.window.createTreeView(COVERAGE_VIEW_ID, { treeDataProvider: this, showCollapseAll: true });
  }

  /** The report the panel shows, for the integration tests. */
  get report(): CoverageReport | undefined {
    return this.#report;
  }

  /** Shows the coverage of document, or keeps the last file when it is not Ruby code on disk. */
  async show(document: vscode.TextDocument | undefined): Promise<void> {
    if (document?.languageId !== "ruby" || document.uri.scheme !== "file") {
      return;
    }
    const folder = vscode.workspace.getWorkspaceFolder(document.uri);
    if (!folder) {
      return;
    }
    const request = ++this.#requests;
    try {
      const report = await inspectCoverage(this.#command(document.uri), folder.uri.fsPath, document.uri.fsPath);
      if (request !== this.#requests) {
        return;
      }
      this.#uri = document.uri;
      this.#folder = folder.uri;
      this.#report = report;
      // An empty message clears it; the API takes no undefined here.
      this.#view.message = coverageMessage(report) ?? "";
      this.#view.description = report.code_path;
    } catch (error) {
      if (request !== this.#requests) {
        return;
      }
      const message = error instanceof InspectError || error instanceof Error ? error.message : String(error);
      this.#log.error(`Could not list the coverage of ${vscode.workspace.asRelativePath(document.uri)}: ${message}`);
      this.#report = undefined;
      this.#view.message = `Omoteura could not list the coverage of this file: ${message}`;
    }
    this.#changed.fire(undefined);
    this.#refreshed.fire(document.uri);
  }

  /** Brings the shown file up to date, after code, specs or test results changed. */
  async refresh(): Promise<void> {
    if (this.#uri) {
      await this.show(await vscode.workspace.openTextDocument(this.#uri));
    }
  }

  getChildren(node?: Node): Node[] {
    if (!this.#report?.enabled) {
      return [];
    }
    if (!node) {
      return coverageGroups(this.#report).map((group) => ({ type: "group", group }));
    }
    if (node.type === "group") {
      return node.group.items.map((item) => ({ type: "item", item }));
    }
    if (node.type === "item") {
      return node.item.examples.map((example) => ({ type: "example", example }));
    }
    return [];
  }

  getTreeItem(node: Node): vscode.TreeItem {
    switch (node.type) {
      case "group": {
        const { group } = node;
        const item = new vscode.TreeItem(group.title, vscode.TreeItemCollapsibleState.Expanded);
        item.description = `${group.covered}/${group.items.length}`;
        return item;
      }
      case "item": {
        const { item } = node;
        const tree = new vscode.TreeItem(
          item.name,
          item.examples.length > 0 ? vscode.TreeItemCollapsibleState.Collapsed : vscode.TreeItemCollapsibleState.None,
        );
        tree.description = coverageDescription(item);
        tree.iconPath = ICONS[coverageStatus(item)];
        const code = this.#open(this.#uri, item.start_line, item.end_line, "Go to Code");
        if (code) {
          tree.command = code;
        }
        return tree;
      }
      case "example": {
        const { example } = node;
        const tree = new vscode.TreeItem(example.description, vscode.TreeItemCollapsibleState.None);
        tree.description = `${example.path}:${example.line}`;
        tree.iconPath =
          example.status === "failed"
            ? ICONS.failing
            : example.status === "passed"
              ? ICONS.covered
              : new vscode.ThemeIcon("beaker");
        const spec = this.#folder && vscode.Uri.joinPath(this.#folder, example.path);
        const open = this.#open(spec, example.line, example.line, "Go to Example");
        if (open) {
          tree.command = open;
        }
        return tree;
      }
    }
  }

  dispose(): void {
    this.#view.dispose();
    this.#changed.dispose();
    this.#refreshed.dispose();
  }

  #open(uri: vscode.Uri | undefined, startLine: number, endLine: number, title: string): vscode.Command | undefined {
    if (!uri) {
      return undefined;
    }
    const selection = new vscode.Range(startLine - 1, 0, endLine - 1, 0);
    return { title, command: "vscode.open", arguments: [uri, { selection }] };
  }
}
