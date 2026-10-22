import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { diagnose } from "../../src/setup.ts";

// The inputs are the messages these failures really print.

describe("diagnose", () => {
  it("recognizes omoteura's own check for an old Ruby", () => {
    const diagnosis = diagnose(
      "omoteura needs Ruby 3.4 or later, but this is Ruby 2.6.10 (/System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/bin/ruby).",
    );

    assert.equal(diagnosis?.problem, "old-ruby");
    assert.match(diagnosis?.message ?? "", /runs on Ruby 2\.6\.10, but needs Ruby 3\.4 or later/);
  });

  it("recognizes an old Ruby failing to load an older omoteura", () => {
    const diagnosis = diagnose(
      "/project/omoteura-core/lib/omoteura/checker.rb:10: warning: constant ::Data is deprecated\n" +
        "/project/omoteura-core/lib/omoteura/checker.rb:10:in `<class:Checker>': undefined method `define' for Data:Class (NoMethodError)",
    );

    assert.equal(diagnosis?.problem, "old-ruby");
  });

  it("recognizes Bundler refusing the gem for this Ruby", () => {
    const diagnosis = diagnose(
      "omoteura-core-0.0.1 requires ruby version >= 3.4, which is incompatible with the current version, 2.6.10",
    );

    assert.equal(diagnosis?.problem, "old-ruby");
  });

  it("recognizes a Gemfile without omoteura", () => {
    const diagnosis = diagnose(
      "bundler: command not found: omoteura\nInstall missing gem executables with `bundle install`",
    );

    assert.equal(diagnosis?.problem, "not-in-gemfile");
    assert.match(diagnosis?.message ?? "", /gem "omoteura", require: false/);
  });

  it("recognizes gems that are not installed", () => {
    const diagnosis = diagnose(
      "Could not find omoteura-0.0.1 in locally installed gems\nRun `bundle install` to install missing gems.",
    );

    assert.equal(diagnosis?.problem, "not-installed");
  });

  it("recognizes a project without a Gemfile", () => {
    assert.equal(diagnose("Could not locate Gemfile or .bundle/ directory")?.problem, "no-gemfile");
  });

  it("recognizes a program that is not on PATH", () => {
    const diagnosis = diagnose("spawn bundle ENOENT");

    assert.equal(diagnosis?.problem, "command-not-found");
    assert.match(diagnosis?.message ?? "", /cannot find bundle/);
  });

  it("leaves other errors alone", () => {
    assert.equal(diagnose('omoteura: diagrams_dir must be a relative path, got "/abs"'), undefined);
  });
});
