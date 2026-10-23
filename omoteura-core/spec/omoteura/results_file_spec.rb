# frozen_string_literal: true

require "json"
require "omoteura/core"

RSpec.describe Omoteura::ResultsFile do
  def example(status, line)
    {id: "x", file_path: "spec/a_spec.rb", line_number: line, full_description: "A #{line}", status: status, message: nil}
  end

  it "writes the examples with a summary, in the version TestResults reads" do
    allow(Coverage).to receive(:running?).and_return(false)

    data = JSON.parse(described_class.generate([example("passed", 1), example("failed", 2), example("pending", 3)]))

    expect(data["version"]).to eq(Omoteura::TestResults::SUPPORTED_VERSION)
    expect(data["summary"]).to eq("examples" => 3, "failures" => 1, "pending" => 1)
    expect(data["examples"].map { |e| e["line_number"] }).to eq([1, 2, 3])
    expect(data).not_to have_key("executed_lines")
  end

  it "takes the colors out of a message" do
    expect(described_class.plain("\e[31mexpected\e[0m: 1")).to eq("expected: 1")
    expect(described_class.plain(nil)).to be_nil
  end
end
