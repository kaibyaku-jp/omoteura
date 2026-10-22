# frozen_string_literal: true

require "omoteura/core"

RSpec.describe Omoteura::SourceIndex do
  def entry(kind, name, start_line, end_line = start_line)
    described_class::Entry.new(kind: kind, name: name, start_line: start_line, end_line: end_line)
  end

  describe "#spec_entries" do
    it "builds full descriptions the way RSpec does" do
      index = described_class.new(<<~RUBY)
        RSpec.describe User, type: :model do
          describe "validations" do
            context "email" do
              it "一意であること" do
                expect(user).not_to be_valid
              end
            end
          end

          describe "#display_name" do
            it "falls back to the email", :focus do
            end
          end

          describe ".find_by_email" do
          end
        end
      RUBY

      expect(index.spec_entries).to eq([
        entry(:spec, "User", 1, 17),
        entry(:spec, "User validations", 2, 8),
        entry(:spec, "User validations email", 3, 7),
        entry(:spec, "User validations email 一意であること", 4, 6),
        entry(:spec, "User#display_name", 10, 13),
        entry(:spec, "User#display_name falls back to the email", 11, 12),
        entry(:spec, "User.find_by_email", 15, 16)
      ])
    end

    it "only attaches #method directly to a group described by a module" do
      index = described_class.new(<<~RUBY)
        describe "users" do
          describe "#count" do
          end
        end
      RUBY

      expect(index.spec_entries.map(&:name)).to eq(["users", "users #count"])
    end

    it "uses a namespaced constant as written" do
      index = described_class.new("describe Admin::User do\nend\n")

      expect(index.spec_entries.map(&:name)).to eq(["Admin::User"])
    end

    it "skips examples and groups whose description is not a literal" do
      index = described_class.new(<<~'RUBY')
        describe User do
          it { is_expected.to be_valid }

          describe "#{prefix} names" do
            it "is unreachable statically" do
            end
          end

          it "is still found" do
          end
        end
      RUBY

      expect(index.spec_entries.map(&:name)).to eq(["User", "User is still found"])
    end

    it "ignores calls named like RSpec methods on other receivers" do
      index = described_class.new("client.describe \"stack\"\n")

      expect(index.spec_entries).to eq([])
    end
  end

  describe "#method_entries" do
    it "finds instance and singleton methods" do
      index = described_class.new(<<~RUBY)
        class User
          def display_name
            name
          end

          def self.find_by_email(email)
          end
        end
      RUBY

      expect(index.method_entries).to eq([
        entry(:method, "display_name", 2, 4),
        entry(:method, "self.find_by_email", 6, 7)
      ])
    end
  end

  describe "#statement_entries" do
    it "records the first line of every statement with its full line range" do
      index = described_class.new(<<~RUBY)
        class User
          validates :email, presence: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
        end
      RUBY

      expect(index.statement_entries).to eq([
        entry(:statement, "class User", 1, 4),
        entry(:statement, "validates :email, presence: true,", 2, 3)
      ])
    end
  end
end
