# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "omoteura/core"

RSpec.describe Omoteura::Checker do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  attr_reader :root

  def write(path, content)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def drawing(*shapes)
    elements = shapes.flat_map do |id, label, link|
      [
        {id: id, type: "rectangle", link: link, boundElements: [{type: "text", id: "#{id}-label"}]},
        {id: "#{id}-label", type: "text", text: label, containerId: id}
      ]
    end
    JSON.generate(type: "excalidraw", elements: elements)
  end

  def problem(file, message, shape = nil)
    described_class::Problem.new(file: file, message: message, shape: shape)
  end

  def run
    described_class.new(Omoteura::Config.load(root)).run
  end

  before do
    write("app/models/user.rb", <<~RUBY)
      class User < ApplicationRecord
        def display_name
        end
      end
    RUBY
    write("spec/models/user_spec.rb", <<~RUBY)
      RSpec.describe User do
        it "has a display name" do
        end
      end
    RUBY
  end

  it "passes a project whose links all resolve" do
    write("ura/app/models/user.excalidraw", drawing(["name", "display_name", "omoteura:#display_name"]))
    write("ura/spec/models/user_spec.excalidraw", drawing(["spec", "spec", "omoteura:#has a display name"], ["memo", "just a note", nil]))

    report = run

    expect(report).to be_ok
    expect(report.diagram_count).to eq(2)
    expect(report.link_count).to eq(2)
  end

  it "passes a project without diagrams" do
    expect(run).to be_ok
  end

  it "reports a broken link with the shape it comes from" do
    write("ura/app/models/user.excalidraw", drawing(["name", "名前の表示", "omoteura:#full_name"]))

    expect(run.problems).to eq([
      problem("ura/app/models/user.excalidraw", "omoteura:#full_name matches nothing in app/models/user.rb", "名前の表示")
    ])
  end

  it "reports a diagram that cannot be read" do
    write("ura/app/models/user.excalidraw", "{")

    expect(run.problems.map(&:file)).to eq(["ura/app/models/user.excalidraw"])
    expect(run.problems.first.message).to start_with("has invalid drawing JSON")
  end

  it "reports a magic comment that points to a missing diagram" do
    write("app/models/user.rb", "# omoteura: ura/shared/user.excalidraw\nclass User; end\n")

    expect(run.problems).to eq([problem("app/models/user.rb", "attaches ura/shared/user.excalidraw, which does not exist")])
  end

  it "reports duplicate magic comments" do
    write("app/models/user.rb", "# omoteura: ura/a.excalidraw\nclass User; end\n# omoteura: ura/b.excalidraw\n")

    expect(run.problems).to eq([problem("app/models/user.rb", "has 2 omoteura magic comments; keep only one")])
  end

  it "reports a magic comment that points outside the project" do
    write("app/models/user.rb", "# omoteura: ../outside.excalidraw\nclass User; end\n")

    expect(run.problems).to eq([problem("app/models/user.rb", "attaches ../outside.excalidraw, which is outside the project")])
  end

  it "reports a diagram whose code file is gone" do
    write("ura/app/models/post.excalidraw.md", "---\nexcalidraw-plugin: parsed\n---\n## Drawing\n```json\n{\"elements\": []}\n```\n")

    expect(run.problems).to eq([problem("ura/app/models/post.excalidraw.md", "is not attached to any code file")])
  end

  it "does not report a shared diagram attached by a magic comment" do
    write("ura/shared/user.excalidraw", drawing)
    write("app/models/user.rb", "# omoteura: ura/shared/user.excalidraw\nclass User; end\n")

    expect(run).to be_ok
  end

  it "counts a shared diagram once" do
    write("ura/shared/user.excalidraw", drawing)
    write("app/models/user.rb", "# omoteura: ura/shared/user.excalidraw\nclass User; end\n")
    write("app/models/admin.rb", "# omoteura: ura/shared/user.excalidraw\nclass Admin; end\n")

    expect(run.diagram_count).to eq(1)
  end

  it "leaves plain notes in the diagrams directory alone" do
    write("ura/README.md", "# Diagrams\n")

    expect(run).to be_ok
  end

  it "skips Ruby files in vendor and tmp" do
    write("vendor/bundle/gems/x/lib/x.rb", "# omoteura: ura/missing.excalidraw\n")
    write("tmp/cache/y.rb", "# omoteura: ura/missing.excalidraw\n")

    expect(run).to be_ok
  end
end
