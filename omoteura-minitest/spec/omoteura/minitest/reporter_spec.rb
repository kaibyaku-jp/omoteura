# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "fileutils"

# Runs Minitest in a separate process on a small project set up the way
# the README describes, so the test covers loading the reporter from
# test_helper.rb alone. ActiveSupport's test "…" is imitated in a few
# lines, so these specs need no Rails.
RSpec.describe "Omoteura::Minitest::Reporter" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  attr_reader :root

  def write(path, content)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def run_tests(env = {}, helper: "require \"omoteura/minitest\"\n")
    write("test/test_helper.rb", "#{helper}require \"minitest/autorun\"\n#{declarative}")
    _out, err, status = Open3.capture3(env, RbConfig.ruby, "-Itest", "test/models/user_test.rb", chdir: root)
    # Older Minitest warns about itself on newer Ruby; nothing else may.
    expect(err.lines.grep_v(%r{/gems/minitest-[^/]+/})).to eq([])
    status
  end

  def results(path = "tmp/omoteura/results.json")
    JSON.parse(File.read(File.join(root, path)))
  end

  def declarative = <<~RUBY
    class DeclarativeTest < Minitest::Test
      def self.test(name, &block)
        define_method("test_\#{name.gsub(/\\s+/, "_")}", &block)
      end
    end
  RUBY

  before do
    write("test/models/user_test.rb", <<~RUBY)
      require "test_helper"

      class UserTest < DeclarativeTest
        test "requires an email" do
          assert true
        end

        test "falls back to the email" do
          assert_equal "aki@example.com", "aki"
        end

        def test_display_name
          skip "not written yet"
        end
      end
    RUBY
  end

  it "writes each test's result, at the line the test starts on" do
    status = run_tests

    expect(status.exitstatus).to eq(1)
    data = results
    expect(data["version"]).to eq(1)
    expect(data["summary"]).to eq("examples" => 3, "failures" => 1, "pending" => 1)
    expect(data["examples"].sort_by { |e| e["line_number"] }.map { |e| e.slice("file_path", "line_number", "full_description", "status") }).to eq([
      {"file_path" => "test/models/user_test.rb", "line_number" => 4, "full_description" => "UserTest requires an email", "status" => "passed"},
      {"file_path" => "test/models/user_test.rb", "line_number" => 8, "full_description" => "UserTest falls back to the email", "status" => "failed"},
      {"file_path" => "test/models/user_test.rb", "line_number" => 12, "full_description" => "UserTest display name", "status" => "pending"}
    ])
  end

  it "includes the failure message and the skip reason" do
    run_tests
    examples = results["examples"].to_h { |e| [e["status"], e["message"]] }

    expect(examples["failed"]).to include('Expected: "aki@example.com"')
    expect(examples["pending"]).to eq("not written yet")
  end

  it "writes to OMOTEURA_RESULTS when it is set" do
    run_tests({"OMOTEURA_RESULTS" => "out/results.json"})

    expect(results("out/results.json")["summary"]["examples"]).to eq(3)
  end

  it "writes nothing unless test_helper.rb requires it" do
    run_tests(helper: "")

    expect(File).not_to exist(File.join(root, "tmp/omoteura/results.json"))
  end

  it "records every test when tests run in parallel" do
    write("test/models/user_test.rb", <<~RUBY)
      require "test_helper"

      class UserTest < DeclarativeTest
        parallelize_me!

        #{(1..20).map { |i| "test \"case #{i}\" do\n    sleep 0.01\n  end" }.join("\n\n  ")}
      end
    RUBY

    run_tests({"MT_CPU" => "4"})

    expect(results["summary"]["examples"]).to eq(20)
  end

  it "records the lines of the project's code that ran, when coverage is measured" do
    write("app/models/greeter.rb", "class Greeter\n  def hello\n    \"hello\"\n  end\n\n  def bye\n    \"bye\"\n  end\nend\n")
    write("test/models/user_test.rb", <<~RUBY)
      require "test_helper"
      require_relative "../../app/models/greeter"

      class UserTest < DeclarativeTest
        test "says hello" do
          assert_equal "hello", Greeter.new.hello
        end
      end
    RUBY

    run_tests(helper: "require \"coverage\"\nCoverage.start(lines: true)\nrequire \"omoteura/minitest\"\n")

    expect(results["executed_lines"]).to eq("app/models/greeter.rb" => [1, 2, 3, 6])
  end
end
