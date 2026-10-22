# frozen_string_literal: true

require "json"
require "omoteura/core"

RSpec.describe Omoteura::LZString do
  vectors = JSON.parse(File.read(File.expand_path("../fixtures/lz_string_vectors.json", __dir__)))

  vectors.each do |vector|
    it "decompresses #{vector["plain"][0, 30].inspect}" do
      expect(described_class.decompress_from_base64(vector["compressed"])).to eq(vector["plain"])
    end
  end

  it "ignores line breaks inside the input" do
    vector = vectors.last
    wrapped = vector["compressed"].scan(/.{1,40}/).join("\n\n")

    expect(described_class.decompress_from_base64(wrapped)).to eq(vector["plain"])
  end

  it "returns nil for corrupt input" do
    expect(described_class.decompress_from_base64("@@@@")).to be_nil
  end
end
