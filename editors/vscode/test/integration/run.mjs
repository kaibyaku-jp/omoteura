// Downloads VS Code (stable, or VSCODE_VERSION) and runs the integration
// tests in it, with the sample project as the workspace.
import { fileURLToPath } from "node:url";
import { runTests } from "@vscode/test-electron";

const extension = fileURLToPath(new URL("../../", import.meta.url));

try {
  await runTests({
    version: process.env.VSCODE_VERSION ?? "stable",
    extensionDevelopmentPath: extension,
    extensionTestsPath: `${extension}dist/test/index.cjs`,
    launchArgs: [`${extension}.vscode-test/sample_project`, "--disable-extensions", "--skip-welcome"],
  });
} catch (error) {
  console.error(error);
  process.exit(1);
}
