// Copies the gem's sample project into .vscode-test/sample_project and
// points the extension at the omoteura executable in this repository, so
// the integration tests run against the current gem without Bundler.
import { execFileSync } from "node:child_process";
import { cp, mkdir, rm, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const repo = fileURLToPath(new URL("../../../../", import.meta.url));
const project = fileURLToPath(new URL("../../.vscode-test/sample_project/", import.meta.url));
// VS Code may not inherit this shell's PATH (on macOS it can find the
// system Ruby instead), so the Ruby running this script is named by path.
const ruby = process.env.OMOTEURA_RUBY ?? execFileSync("ruby", ["-e", "print RbConfig.ruby"], { encoding: "utf8" });

await rm(project, { recursive: true, force: true });
await cp(`${repo}spec/fixtures/sample_project`, project, { recursive: true });
await mkdir(`${project}.vscode`, { recursive: true });
await writeFile(
  `${project}.vscode/settings.json`,
  `${JSON.stringify(
    {
      "omoteura.command": [ruby, "-I", `${repo}omoteura-core/lib`, `${repo}omoteura-core/exe/omoteura`],
    },
    null,
    2,
  )}\n`,
);
console.log(`Prepared ${project}`);
