# frozen_string_literal: true

require "omoteura/core"

RSpec.describe Omoteura do
  it "has a version RubyGems accepts" do
    expect(Gem::Version.correct?(Omoteura::VERSION)).to be(true)
  end
end
