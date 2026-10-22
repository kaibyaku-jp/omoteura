// Recognizes the usual reasons running omoteura fails and says how to fix
// each, so a setup problem does not look like a bug in the extension.

export type SetupProblem = "old-ruby" | "not-in-gemfile" | "not-installed" | "no-gemfile" | "command-not-found";

export interface Diagnosis {
  problem: SetupProblem;
  /** One sentence for a notification. */
  message: string;
}

const RULES: [RegExp, (match: RegExpMatchArray) => Diagnosis][] = [
  [
    /omoteura needs Ruby ([\d.]+) or later, but this is Ruby ([\d.]+)/,
    (m) => ({
      problem: "old-ruby",
      message: `omoteura runs on Ruby ${m[2]}, but needs Ruby ${m[1]} or later. VS Code may not see the Ruby your version manager selects: start it from a terminal in the project, or set omoteura.command.`,
    }),
  ],
  [
    // Older omoteura releases, or Bundler refusing the gem for this Ruby.
    /requires ruby version|constant ::Data is deprecated|undefined method [`']define' for Data/,
    () => ({
      problem: "old-ruby",
      message:
        "omoteura runs on a Ruby that is too old. VS Code may not see the Ruby your version manager selects: start it from a terminal in the project, or set omoteura.command.",
    }),
  ],
  [
    /bundler: command not found: omoteura/,
    () => ({
      problem: "not-in-gemfile",
      message:
        'The project\'s Gemfile does not include omoteura. Add gem "omoteura", require: false and run bundle install.',
    }),
  ],
  [
    /Could not find .+ in (?:locally installed gems|any of the sources)|Run `bundle install` to install missing gems/,
    () => ({
      problem: "not-installed",
      message: "The project's gems are not installed. Run bundle install in the project.",
    }),
  ],
  [
    /Could not locate Gemfile/,
    () => ({
      problem: "no-gemfile",
      message:
        'This project has no Gemfile, so bundle exec cannot run omoteura. Set omoteura.command to ["omoteura"] to use an installed gem.',
    }),
  ],
  [
    /spawn (\S+) ENOENT/,
    (m) => ({
      problem: "command-not-found",
      message: `VS Code cannot find ${m[1]}. Start VS Code from a terminal so it sees your PATH, or set omoteura.command to a full path.`,
    }),
  ],
];

export function diagnose(error: string): Diagnosis | undefined {
  for (const [pattern, diagnosis] of RULES) {
    const match = error.match(pattern);
    if (match) {
      return diagnosis(match);
    }
  }
  return undefined;
}
