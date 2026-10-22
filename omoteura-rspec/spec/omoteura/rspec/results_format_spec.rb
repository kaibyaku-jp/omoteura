# frozen_string_literal: true

require "omoteura/core"
require "omoteura/rspec/formatter"

RSpec.describe "The results file format" do
  it "is written by the formatter in the version omoteura-core reads" do
    expect(Omoteura::RSpec::Formatter::FORMAT_VERSION).to eq(Omoteura::TestResults::SUPPORTED_VERSION)
  end
end
