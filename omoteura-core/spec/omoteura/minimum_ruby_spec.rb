# frozen_string_literal: true

require "omoteura/minimum_ruby"

RSpec.describe "Omoteura.ruby_too_old_message" do
  it "explains a Ruby older than the minimum" do
    expect(Omoteura.ruby_too_old_message("2.6.10", "/usr/bin/ruby"))
      .to eq("omoteura needs Ruby 3.4 or later, but this is Ruby 2.6.10 (/usr/bin/ruby).")
  end

  it "accepts the minimum and later versions, including previews" do
    expect(Omoteura.ruby_too_old_message("3.4.0", "/usr/bin/ruby")).to be_nil
    expect(Omoteura.ruby_too_old_message("4.1.0", "/usr/bin/ruby")).to be_nil
  end

  it "accepts the Ruby running the specs" do
    expect(Omoteura.ruby_too_old_message).to be_nil
  end
end
