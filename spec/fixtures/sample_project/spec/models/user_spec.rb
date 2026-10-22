# frozen_string_literal: true

require_relative "../../app/models/user"

RSpec.describe User do
  describe "validations" do
    it "requires an email" do
      expect(User.new(email: nil)).not_to be_valid
    end
  end

  describe "#display_name" do
    it "uses the name" do
      expect(User.new(name: "Aki", email: "aki@example.com").display_name).to eq("Aki")
    end

    # Fails on purpose, so the sample has a failing example to show.
    it "falls back to the email" do
      expect(User.new(email: "aki@example.com").display_name).to eq("aki@example.com")
    end
  end
end
