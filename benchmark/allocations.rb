# frozen_string_literal: true

# Measures allocations and time of the main code paths on generated
# inputs sized like a large Rails project.
#
#   bundle exec ruby benchmark/allocations.rb
#
#   LZ_STRING_INPUT=compressed.txt bundle exec ruby benchmark/allocations.rb
#
# Results vary a little between Ruby versions; compare runs on the same one.

require "fileutils"
require "json"
require "memory_profiler"
require "tmpdir"
require "omoteura/core"

def measure(label)
  yield # warm up caches and autoloads outside the measurement
  report = MemoryProfiler.report { yield }
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
  puts format("%-44s %9d objects %11d bytes %9.1f ms", label, report.total_allocated, report.total_allocated_memsize, elapsed)
end

def spec_source(groups:, examples:)
  body = (1..groups).map do |g|
    its = (1..examples).map { |e| "    it \"behaves #{e}\" do\n      expect(user.value_#{g}_#{e}).to eq(#{e})\n    end\n" }.join("\n")
    "  describe \"#method_#{g}\" do\n#{its}  end\n"
  end.join("\n")
  "RSpec.describe User do\n#{body}end\n"
end

def model_source(methods:)
  body = (1..methods).map { |m| "  validates :field_#{m}, presence: true\n\n  def method_#{m}\n    field_#{m}.to_s\n  end\n" }.join("\n")
  "class User < ApplicationRecord\n#{body}end\n"
end

def drawing(elements:)
  JSON.generate(type: "excalidraw", elements: (1..elements).map do |i|
    {id: "shape-#{i}", type: "rectangle", x: i, y: i * 2, width: 120, height: 60, strokeColor: "#1e1e1e",
     link: (i % 4 == 0) ? "omoteura:#behaves #{i % 10 + 1}" : nil, isDeleted: false}
  end)
end

Dir.mktmpdir do |root|
  spec = spec_source(groups: 100, examples: 10)
  model = model_source(methods: 300)
  plain = model.gsub("validates", "validate")
  json = drawing(elements: 2000)

  puts "Inputs: spec #{spec.lines.size} lines, model #{model.lines.size} lines, drawing #{json.bytesize / 1024} KB"
  puts

  measure("MagicComment.find, no marker x1000") { 1000.times { Omoteura::MagicComment.find(plain) } }
  measure("SourceIndex.new, spec") { Omoteura::SourceIndex.new(spec) }
  measure("SourceIndex.new, model") { Omoteura::SourceIndex.new(model) }

  FileUtils.mkdir_p(File.join(root, "spec/models"))
  File.write(File.join(root, "spec/models/user_spec.rb"), spec)
  config = Omoteura::Config.load(root)
  links = (1..100).flat_map { |g| ["omoteura:#method_#{g} behaves 3", "omoteura:#method_#{g}"] }
  measure("LinkResolver#resolve x200, one file") do
    resolver = Omoteura::LinkResolver.new(config)
    links.each { |link| resolver.resolve(link, context_path: "spec/models/user_spec.rb") }
  end

  # The repository has no lz-string compressor; pass a file made with
  # lz-string's compressToBase64 to include the decoder.
  if (lz_path = ENV["LZ_STRING_INPUT"])
    compressed = File.read(lz_path)
    measure("LZString.decompress_from_base64, #{compressed.bytesize / 1024} KB") { Omoteura::LZString.decompress_from_base64(compressed) }
  end

  File.write(File.join(root, "drawing.excalidraw"), json)
  measure("Diagram.load, 2000 elements") { Omoteura::Diagram.load(File.join(root, "drawing.excalidraw")) }

  200.times do |i|
    path = File.join(root, "app/models/model_#{i}.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, model_source(methods: 20))
  end
  20.times do |i|
    path = File.join(root, "ura/app/models/model_#{i}.excalidraw")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(type: "excalidraw", elements: (1..20).map { |m| {id: "s#{m}", type: "rectangle", link: "omoteura:#method_#{m}"} }))
  end
  measure("Checker#run, 200 code files, 20 diagrams") { Omoteura::Checker.new(Omoteura::Config.load(root)).run }
end
