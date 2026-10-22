# frozen_string_literal: true

require "fileutils"
require "memory_profiler"
require "tmpdir"
require "omoteura/core"

# Guards the allocation work measured by `rake bench`. Exact counts change
# between Ruby versions, so these check properties that should hold on any
# of them: nothing allocated, work done once, overhead that stays bounded.
RSpec.describe "Allocations" do
  # Objects allocated by the block, less what measuring itself allocates.
  def allocated_objects
    overhead = count_objects {}
    count_objects { yield } - overhead
  end

  def count_objects
    before = GC.stat(:total_allocated_objects)
    yield
    GC.stat(:total_allocated_objects) - before
  end

  def allocated_bytes(&block)
    MemoryProfiler.report(&block).total_allocated_memsize
  end

  def spec_source(groups)
    body = (1..groups).map do |g|
      "  describe \"#method_#{g}\" do\n" +
        (1..10).map { |e| "    it \"behaves #{e}\" do\n      expect(value).to eq(#{e})\n    end\n" }.join +
        "  end\n"
    end
    "RSpec.describe User do\n#{body.join}end\n"
  end

  it "does not allocate when looking for a magic comment in a file without one" do
    source = "class User\n  def name\n  end\nend\n" * 50
    Omoteura::MagicComment.find(source)

    expect(allocated_objects { 100.times { Omoteura::MagicComment.find(source) } }).to eq(0)
  end

  it "indexes a file with little memory beyond Prism's own parse" do
    source = spec_source(100)
    Omoteura::SourceIndex.new(source)

    ratio = allocated_bytes { Omoteura::SourceIndex.new(source) }.fdiv(allocated_bytes { Prism.parse(source) })

    # About 1.6 now; slicing each statement's whole source to name it made it about 2.4.
    expect(ratio).to be < 2
  end

  context "when resolving links" do
    around do |example|
      Dir.mktmpdir do |dir|
        @root = File.realpath(dir)
        FileUtils.mkdir_p(File.join(@root, "spec/models"))
        File.write(File.join(@root, "spec/models/user_spec.rb"), spec_source(200))
        example.run
      end
    end

    let(:resolver) { Omoteura::LinkResolver.new(Omoteura::Config.load(@root)) }

    it "parses each file once" do
      expect(Omoteura::SourceIndex).to receive(:parse_file).once.and_call_original

      3.times { |i| resolver.resolve("omoteura:#method_#{i + 1} behaves 2", context_path: "spec/models/user_spec.rb") }
    end

    it "allocates for a link about as much in a large file as in a small one" do
      link = "omoteura:#method_7 behaves 3"
      resolver.resolve(link, context_path: "spec/models/user_spec.rb")

      # About 2,200 spec entries are scanned; full-size result arrays cost about 9 KB per scan.
      expect(allocated_bytes { resolver.resolve(link, context_path: "spec/models/user_spec.rb") }).to be < 4_000
    end
  end
end
