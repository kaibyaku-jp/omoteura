# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "omoteura/core"

RSpec.describe Omoteura::CoverageReport do
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

  def report(path, results: Omoteura::TestResults.new([]))
    described_class.new(Omoteura::Config.load(root), results: results).report(path)
  end

  def coverage(path, **options)
    report(path, **options)[:items].map { |item| [item[:name], item[:covered], item[:examples].map { |e| e[:line] }] }
  end

  before do
    write("app/models/user.rb", <<~RUBY)
      class User < ApplicationRecord
        has_many :posts
        belongs_to :team
        validates :email, presence: true
        before_save :downcase_email
        enum role: { member: 0, admin: 1 }

        def display_name
        end

        def self.find_by_email(email)
        end
      end
    RUBY
    write("spec/models/user_spec.rb", <<~RUBY)
      RSpec.describe User do
        it { is_expected.to have_many(:posts) }

        it "requires an email" do
          expect(User.new(email: nil)).not_to be_valid
        end

        describe "#display_name" do
          it "uses the name" do
          end
        end

        it "lets admins in" do
          expect(User.new(role: :admin)).to be_admin
        end
      end
    RUBY
  end

  it "says which declarations and public methods an example names, in its description or its code" do
    expect(coverage("app/models/user.rb")).to eq([
      ["validates :email, presence: true", true, [4]],
      ["has_many :posts", true, [2]],
      ["belongs_to :team", false, []],
      ["before_save :downcase_email", false, []],
      ["enum role: { member: 0, admin: 1 }", true, [13]],
      ["display_name", true, [9]],
      ["self.find_by_email", false, []]
    ])
  end

  it "reports where each item is, the examples and their last results" do
    results = Omoteura::TestResults.new([
      Omoteura::TestResults::Example.new(file_path: "./spec/models/user_spec.rb", line_number: 9,
        full_description: "User#display_name uses the name", status: "failed", message: "boom")
    ])

    data = report("app/models/user.rb", results: results)

    expect(data.slice(:version, :code_path, :enabled, :spec_paths))
      .to eq(version: 1, code_path: "app/models/user.rb", enabled: true, spec_paths: ["spec/models/user_spec.rb"])
    expect(data[:items].find { |item| item[:name] == "display_name" })
      .to include(kind: "methods", start_line: 8, end_line: 9,
        examples: [{path: "spec/models/user_spec.rb", line: 9, description: "User#display_name uses the name", status: "failed"}])
  end

  it "counts the description RSpec generated in the last run" do
    write("spec/models/user_spec.rb", "RSpec.describe User do\n  it { is_expected.to belong_to(:owner) }\nend\n")
    results = Omoteura::TestResults.new([
      Omoteura::TestResults::Example.new(file_path: "spec/models/user_spec.rb", line_number: 2,
        full_description: "User is expected to belong to team required: true", status: "passed", message: nil)
    ])

    expect(coverage("app/models/user.rb", results: results).assoc("belongs_to :team")).to eq(["belongs_to :team", true, [2]])
  end

  describe "with the lines the last run executed" do
    before do
      write("app/models/post.rb", "class Post\n  has_many :tags\n\n  def title\n    \"t\"\n  end\n\n  def slug\n    \"s\"\n  end\n\n  def empty\n  end\nend\n")
    end

    def judged(executed_lines)
      results = Omoteura::TestResults.new([], executed_lines: executed_lines)
      report("app/models/post.rb", results: results)[:items].map { |item| [item[:name], item[:covered], item[:executed]] }
    end

    it "counts a method whose body ran, and says which did not; declarations and empty methods cannot tell" do
      expect(judged("app/models/post.rb" => [1, 2, 4, 5, 8, 12])).to eq([
        ["has_many :tags", false, nil],
        ["title", true, true],
        ["slug", false, false],
        ["empty", false, nil]
      ])
    end

    it "cannot tell for a file the run did not load" do
      expect(judged({}).map(&:last)).to eq([nil, nil, nil, nil])
    end
  end

  it "finds a Minitest test for the file, by Rails' conventions" do
    write("spec/models/user_spec.rb", "")
    File.delete(File.join(root, "spec/models/user_spec.rb"))
    write("test/models/user_test.rb", <<~RUBY)
      class UserTest < ActiveSupport::TestCase
        test "requires an email" do
        end

        test "display name uses the name" do
        end
      end
    RUBY

    data = report("app/models/user.rb")

    expect(data[:spec_paths]).to eq(["test/models/user_test.rb"])
    expect(data[:items].to_h { |item| [item[:name], item[:examples].map { |e| e[:line] }] }).to include(
      "validates :email, presence: true" => [2], "display_name" => [5], "belongs_to :team" => []
    )
  end

  it "uses both a spec and a test when a project has both" do
    write("test/models/user_test.rb", "class UserTest < ActiveSupport::TestCase\n  test \"has a team\" do\n  end\nend\n")

    data = report("app/models/user.rb")

    expect(data[:spec_paths]).to eq(["spec/models/user_spec.rb", "test/models/user_test.rb"])
    expect(data[:items].find { |item| item[:name] == "belongs_to :team" }[:examples]).to eq([
      {path: "test/models/user_test.rb", line: 2, description: "UserTest has a team", status: nil}
    ])
  end

  it "lists the items as untested when the file has no spec" do
    write("app/models/post.rb", "class Post\n  def title\n  end\nend\n")

    expect(report("app/models/post.rb")).to include(spec_paths: [], items: [
      {kind: "methods", name: "title", start_line: 2, end_line: 3, covered: false, executed: nil, examples: []}
    ])
  end

  it "finds the test of code under lib with or without lib in the path" do
    write("lib/billing/invoice.rb", "class Invoice\n  def total\n  end\nend\n")
    write("test/lib/billing/invoice_test.rb", "class InvoiceTest < Minitest::Test\n  def test_total\n  end\nend\n")

    expect(report("lib/billing/invoice.rb")[:spec_paths]).to eq(["test/lib/billing/invoice_test.rb"])
    expect(coverage("lib/billing/invoice.rb")).to eq([["total", true, [2]]])
  end

  it "finds the spec of code under lib with or without lib in the spec path" do
    write("lib/billing/invoice.rb", "class Invoice\n  def total\n  end\nend\n")
    write("spec/lib/billing/invoice_spec.rb", "RSpec.describe Invoice do\n  it \"adds up the total\" do\n  end\nend\n")

    expect(report("lib/billing/invoice.rb")[:spec_paths]).to eq(["spec/lib/billing/invoice_spec.rb"])
    expect(coverage("lib/billing/invoice.rb")).to eq([["total", true, [2]]])
  end

  it "reports nothing when the coverage panel is turned off" do
    write(".omoteura.yml", "coverage_panel: false\n")

    expect(report("app/models/user.rb")).to eq(version: 1, code_path: "app/models/user.rb", enabled: false, spec_paths: [], items: [])
  end
end
