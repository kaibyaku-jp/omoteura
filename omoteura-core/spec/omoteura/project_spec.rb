# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "omoteura/core"

RSpec.describe Omoteura::Project do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  attr_reader :root

  def write(path, content = "")
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def code_paths
    described_class.new(Omoteura::Config.load(root)).code_paths
  end

  it "lists the project's Ruby files, sorted" do
    write("app/models/user.rb")
    write("spec/models/user_spec.rb")
    write("lib/tasks/setup.rb")

    expect(code_paths).to eq(["app/models/user.rb", "lib/tasks/setup.rb", "spec/models/user_spec.rb"])
  end

  it "leaves out vendored, generated and diagram directories" do
    write("app/models/user.rb")
    %w[vendor tmp log node_modules coverage pkg ura].each { |dir| write("#{dir}/x.rb") }

    expect(code_paths).to eq(["app/models/user.rb"])
  end

  it "adds existing non-Ruby files named in the attach setting" do
    write("app/views/users/show.html.erb")
    write(".omoteura.yml", <<~YAML)
      attach:
        app/views/users/show.html.erb: ura/shared/user.excalidraw
        app/views/users/missing.html.erb: ura/shared/user.excalidraw
    YAML

    expect(code_paths).to eq(["app/views/users/show.html.erb"])
  end
end
