# frozen_string_literal: true

require "rubygems"
require_relative "../omoteura-core/lib/omoteura/core/version"

# Guards the four gemspecs, which are easy to get subtly wrong because
# they live in different directories but are released together.
RSpec.describe "Gem packaging" do
  root = File.expand_path("..", __dir__)
  gems = {
    "omoteura" => root,
    "omoteura-core" => File.join(root, "omoteura-core"),
    "omoteura-rails" => File.join(root, "omoteura-rails"),
    "omoteura-rspec" => File.join(root, "omoteura-rspec")
  }

  gems.each do |name, dir|
    describe name do
      subject(:spec) { Dir.chdir(dir) { Gem::Specification.load("#{name}.gemspec") } }

      it "ships its LICENSE and every Ruby file under lib" do
        lib_files = Dir.glob("lib/**/*.rb", base: dir)

        expect(spec.files).to include("LICENSE", *lib_files)
      end

      it "has the shared version" do
        expect(spec.version.to_s).to eq(Omoteura::VERSION)
      end

      it "pins the other omoteura gems to the same version" do
        omoteura_deps = spec.runtime_dependencies.select { |d| d.name.start_with?("omoteura") }

        expect(omoteura_deps.map(&:requirement)).to all(eq(Gem::Requirement.new(Omoteura::VERSION)))
      end
    end
  end

  %w[omoteura-core omoteura-rails omoteura-rspec].each do |name|
    it "keeps #{name}/LICENSE identical to the root LICENSE" do
      expect(File.read(File.join(root, name, "LICENSE"))).to eq(File.read(File.join(root, "LICENSE")))
    end
  end
end
