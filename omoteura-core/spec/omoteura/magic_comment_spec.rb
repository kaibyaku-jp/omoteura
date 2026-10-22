# frozen_string_literal: true

require "omoteura/core"

RSpec.describe Omoteura::MagicComment do
  describe ".find" do
    it "finds a comment before the code" do
      source = <<~RUBY
        # frozen_string_literal: true

        # omoteura: ura/shared/user-validations.excalidraw.md
        class User < ApplicationRecord
        end
      RUBY

      expect(described_class.find(source)).to eq("ura/shared/user-validations.excalidraw.md")
    end

    it "finds a comment after the code" do
      source = <<~RUBY
        class User < ApplicationRecord
        end

        # omoteura: ura/shared/user-validations.excalidraw.md
      RUBY

      expect(described_class.find(source)).to eq("ura/shared/user-validations.excalidraw.md")
    end

    it "finds a comment in a file without code" do
      expect(described_class.find("# omoteura: ura/notes.excalidraw\n")).to eq("ura/notes.excalidraw")
    end

    it "tolerates missing and extra spaces" do
      expect(described_class.find("#omoteura:   ura/a.excalidraw   \nfoo\n")).to eq("ura/a.excalidraw")
    end

    it "ignores a comment between statements" do
      source = <<~RUBY
        class User < ApplicationRecord
          # omoteura: ura/inside.excalidraw
          validates :email, presence: true
        end
      RUBY

      expect(described_class.find(source)).to be_nil
    end

    it "ignores a comment that follows code on the same line" do
      source = <<~RUBY
        class User < ApplicationRecord
        end # omoteura: ura/trailing.excalidraw
      RUBY

      expect(described_class.find(source)).to be_nil
    end

    it "ignores the text inside strings and heredocs" do
      source = <<~RUBY
        TEMPLATE = <<~TEXT
          # omoteura: ura/heredoc.excalidraw
        TEXT
        NAME = "# omoteura: ura/string.excalidraw"
      RUBY

      expect(described_class.find(source)).to be_nil
    end

    it "ignores =begin blocks" do
      source = <<~RUBY
        =begin
        # omoteura: ura/embdoc.excalidraw
        =end
        class User; end
      RUBY

      expect(described_class.find(source)).to be_nil
    end

    it "returns nil when there is no magic comment" do
      expect(described_class.find("class User; end\n")).to be_nil
    end

    it "raises when the file has more than one magic comment" do
      source = <<~RUBY
        # omoteura: ura/first.excalidraw
        class User; end
        # omoteura: ura/second.excalidraw
      RUBY

      expect { described_class.find(source, path: "app/models/user.rb") }
        .to raise_error(described_class::Duplicate, "app/models/user.rb has 2 omoteura magic comments; keep only one")
    end
  end
end
