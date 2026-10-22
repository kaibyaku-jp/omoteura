# frozen_string_literal: true

require "omoteura/core"

RSpec.describe Omoteura::Outline do
  def items(source, **options)
    described_class.new(Omoteura::SourceIndex.new(source)).items(**options).map { |item| [item.kind, item.entry.name, item.entry.start_line] }
  end

  let(:model) do
    <<~RUBY
      class User < ApplicationRecord
        def initialize(attributes = {})
        end

        def display_name
        end

        has_many :posts
        validates :email, presence: true
        after_commit :notify
        scope :active, -> { where(active: true) }
        enum :role, { member: 0 }

        protected def compare
        end

        private

        def secret
        end
      end
    RUBY
  end

  it "groups declarations by kind, in a fixed order, then public methods other than initialize" do
    expect(items(model)).to eq([
      ["validations", "validates :email, presence: true", 9],
      ["associations", "has_many :posts", 8],
      ["callbacks", "after_commit :notify", 10],
      ["scopes", "scope :active, -> { where(active: true) }", 11],
      ["enums", "enum :role, { member: 0 }", 12],
      ["methods", "display_name", 5]
    ])
  end

  it "gives only the kinds asked for" do
    expect(items(model, only: %w[methods associations]).map(&:first)).to eq(%w[associations methods])
  end

  it "keeps public methods of a class after another class's private section" do
    source = "class A\n  private\n  def a\n  end\nend\n\nclass B\n  def b\n  end\nend\n"

    expect(items(source)).to eq([["methods", "b", 8]])
  end
end
