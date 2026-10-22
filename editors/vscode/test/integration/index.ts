import * as path from "node:path";
import Mocha from "mocha";

// Entry point that VS Code calls to run the integration tests.
export function run(): Promise<void> {
  const mocha = new Mocha({ ui: "bdd", timeout: 30_000, color: true });
  mocha.addFile(path.join(__dirname, "extension.test.cjs"));
  return new Promise((resolve, reject) => {
    mocha.run((failures) => (failures > 0 ? reject(new Error(`${failures} integration tests failed`)) : resolve()));
  });
}
