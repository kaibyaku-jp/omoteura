# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "omoteura/core"

RSpec.describe Omoteura::LinkCandidates do
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

  def candidates(path)
    described_class.new(Omoteura::Config.load(root)).for(path).map { |c| [c.kind, c.label, c.line, c.link] }
  end

  it "offers every example group and example of a spec, by its full description" do
    write("spec/models/user_spec.rb", <<~RUBY)
      RSpec.describe User do
        describe "#display_name" do
          it "uses the name" do
          end
        end
      end
    RUBY

    expect(candidates("spec/models/user_spec.rb")).to eq([
      ["group", "User", 1, "omoteura:#User"],
      ["group", "User#display_name", 2, "omoteura:#User#display_name"],
      ["example", "User#display_name uses the name", 3, "omoteura:#User#display_name uses the name"]
    ])
  end

  it "offers a Minitest test class and its tests, written either way" do
    write("test/models/user_test.rb", <<~RUBY)
      class UserTest < ActiveSupport::TestCase
        test "requires an email" do
        end

        def test_display_name
        end
      end
    RUBY

    expect(candidates("test/models/user_test.rb")).to eq([
      ["group", "UserTest", 1, "omoteura:#UserTest"],
      ["example", "UserTest requires an email", 2, "omoteura:#UserTest requires an email"],
      ["example", "UserTest test_display_name", 5, "omoteura:#UserTest test_display_name"]
    ])
  end

  it "leaves out examples no link can single out" do
    write("spec/models/post_spec.rb", "RSpec.describe Post do\n  it \"works\" do\n  end\n  it \"works\" do\n  end\nend\n")

    expect(candidates("spec/models/post_spec.rb").map(&:first)).to eq(["group"])
  end

  it "offers the declarations and every method of other code, private ones too, in line order" do
    write("app/models/user.rb", <<~RUBY)
      class User < ApplicationRecord
        validates :email, presence: true
        has_many :posts, dependent: :destroy

        def display_name
        end

        private

        def secret
        end
      end
    RUBY

    expect(candidates("app/models/user.rb")).to eq([
      ["validations", "validates :email, presence: true", 2, "omoteura:#validates :email"],
      ["associations", "has_many :posts, dependent: :destroy", 3, "omoteura:#has_many :posts"],
      ["methods", "display_name", 5, "omoteura:#display_name"],
      ["methods", "secret", 10, "omoteura:#secret"]
    ])
  end
end
