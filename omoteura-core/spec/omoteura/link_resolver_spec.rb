# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "omoteura/core"

RSpec.describe Omoteura::LinkResolver do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  attr_reader :root

  subject(:resolver) { described_class.new(Omoteura::Config.load(root)) }

  def write(path, content)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def target(path, start_line, end_line)
    described_class::Target.new(path: path, start_line: start_line, end_line: end_line)
  end

  before do
    write("spec/models/user_spec.rb", <<~RUBY)
      RSpec.describe User do
        describe "validations" do
          context "email" do
            it "一意であること" do
            end
          end

          context "name" do
            it "必須であること" do
            end
          end

          context "nickname" do
            it "必須であること" do
            end
          end
        end
      end
    RUBY

    write("app/models/user.rb", <<~RUBY)
      class User < ApplicationRecord
        validates :email, presence: true,
                          format: { with: URI::MailTo::EMAIL_REGEXP }
        validates :email_confirmation, presence: true

        def display_name
          name.presence || email
        end
      end
    RUBY
  end

  context "with a spec description" do
    it "resolves a full description in the attached file" do
      result = resolver.resolve("omoteura:#User validations email 一意であること", context_path: "spec/models/user_spec.rb")

      expect(result).not_to be_broken
      expect(result.target).to eq(target("spec/models/user_spec.rb", 4, 5))
    end

    it "resolves a trailing part when it is unique" do
      result = resolver.resolve("omoteura:#email 一意であること", context_path: "spec/models/user_spec.rb")

      expect(result.target).to eq(target("spec/models/user_spec.rb", 4, 5))
    end

    it "resolves a group" do
      result = resolver.resolve("omoteura:#validations email", context_path: "spec/models/user_spec.rb")

      expect(result.target).to eq(target("spec/models/user_spec.rb", 3, 6))
    end

    it "resolves a method name described by RSpec's #method convention" do
      write("spec/models/post_spec.rb", <<~RUBY)
        RSpec.describe Post do
          describe "#title" do
            it "is required" do
            end
          end

          describe ".published" do
          end
        end
      RUBY

      expect(resolver.resolve("omoteura:spec/models/post_spec.rb#title is required").target)
        .to eq(target("spec/models/post_spec.rb", 3, 4))
      expect(resolver.resolve("omoteura:spec/models/post_spec.rb#title").target)
        .to eq(target("spec/models/post_spec.rb", 2, 5))
      expect(resolver.resolve("omoteura:spec/models/post_spec.rb#published").target)
        .to eq(target("spec/models/post_spec.rb", 7, 8))
    end

    it "does not match a fragment that starts inside a method name" do
      write("spec/models/post_spec.rb", "RSpec.describe Post do\n  describe \"#subtitle\" do\n  end\nend\n")

      expect(resolver.resolve("omoteura:spec/models/post_spec.rb#title")).to be_broken
    end

    it "requires a trailing part to start at a word boundary" do
      result = resolver.resolve("omoteura:#ail 一意であること", context_path: "spec/models/user_spec.rb")

      expect(result).to be_broken
      expect(result.error).to eq("omoteura:#ail 一意であること matches nothing in spec/models/user_spec.rb")
    end

    it "reports a trailing part that matches several examples" do
      result = resolver.resolve("omoteura:#必須であること", context_path: "spec/models/user_spec.rb")

      expect(result.error).to eq("omoteura:#必須であること matches 2 places in spec/models/user_spec.rb (lines 9, 14)")
    end

    it "resolves a description in another file" do
      result = resolver.resolve("omoteura:spec/models/user_spec.rb#name 必須であること", context_path: "app/models/user.rb")

      expect(result.target).to eq(target("spec/models/user_spec.rb", 9, 10))
    end
  end

  context "with application code" do
    it "resolves a method name" do
      result = resolver.resolve("omoteura:app/models/user.rb#display_name")

      expect(result.target).to eq(target("app/models/user.rb", 6, 8))
    end

    it "resolves the start of a statement to its full line range" do
      result = resolver.resolve("omoteura:#validates :email", context_path: "app/models/user.rb")

      expect(result.target).to eq(target("app/models/user.rb", 2, 3))
    end

    it "does not let a statement prefix stop in the middle of a name" do
      result = resolver.resolve("omoteura:#validates :email_confirmation", context_path: "app/models/user.rb")

      expect(result.target).to eq(target("app/models/user.rb", 4, 4))
    end
  end

  it "resolves a link without a fragment to the whole file" do
    expect(resolver.resolve("omoteura:app/models/user.rb").target).to eq(target("app/models/user.rb", 1, 9))
  end

  it "resolves a bare omoteura: link to the whole attached file" do
    expect(resolver.resolve("omoteura:", context_path: "app/models/user.rb").target).to eq(target("app/models/user.rb", 1, 9))
  end

  describe "broken links" do
    it "reports a missing file" do
      expect(resolver.resolve("omoteura:app/models/post.rb#title").error)
        .to eq("omoteura:app/models/post.rb#title points to app/models/post.rb, which does not exist")
    end

    it "reports a path outside the project" do
      expect(resolver.resolve("omoteura:../secret.rb#x").error).to eq("omoteura:../secret.rb#x points outside the project")
    end

    it "reports a fragment-only link on a diagram that is not attached to a file" do
      expect(resolver.resolve("omoteura:#display_name").error)
        .to eq("omoteura:#display_name has no file and the diagram is not attached to one")
    end

    it "reports an empty fragment" do
      expect(resolver.resolve("omoteura:app/models/user.rb#  ").error).to eq("omoteura:app/models/user.rb#   has an empty #fragment")
    end
  end
end
