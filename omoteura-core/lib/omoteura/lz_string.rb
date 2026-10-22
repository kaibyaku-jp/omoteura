# frozen_string_literal: true

module Omoteura
  # lz-string's compressToBase64 format, which the Obsidian Excalidraw
  # plugin uses for ```compressed-json blocks.
  # Port of https://github.com/pieroxy/lz-string (MIT).
  module LZString
    BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
    # Value of each byte of the alphabet, indexed by byte; anything else reads as 0.
    BASE64_BYTE_VALUES = Array.new(256, 0).tap { |table| BASE64_ALPHABET.each_byte.with_index { |b, i| table[b] = i } }.freeze
    WHITESPACE = " \t\r\n\f\v"

    module_function

    # Compresses a UTF-8 string to the same output as lz-string's
    # compressToBase64.
    def compress_to_base64(input)
      result = compress(input.encode(Encoding::UTF_16BE).unpack("n*"), 6)
      result << "=" * ((4 - result.size % 4) % 4)
    end

    # Returns the decompressed UTF-8 string, or nil if the input is corrupt.
    def decompress_from_base64(input)
      input = input.delete(WHITESPACE)
      return "" if input.empty?

      values = input.bytes
      values.map! { |b| BASE64_BYTE_VALUES[b] }
      decompress(values, 32)
    end

    # Dictionary entries are UTF-16BE byte strings, because lz-string works on
    # JavaScript's UTF-16 code units rather than on characters. They are never
    # modified, so single code units are shared through the units cache.
    def decompress(values, reset_value)
      reader = BitReader.new(values, reset_value)
      units = {}
      dictionary = [nil, nil, nil]
      enlarge_in = 4
      num_bits = 3

      c =
        case reader.read(2)
        when 0 then unit(units, reader.read(8))
        when 1 then unit(units, reader.read(16))
        else return ""
        end
      dictionary << c
      w = c
      result = c.dup

      loop do
        return nil if reader.exhausted?

        code = reader.read(num_bits)
        case code
        when 0, 1
          dictionary << unit(units, reader.read((code == 0) ? 8 : 16))
          code = dictionary.size - 1
          enlarge_in -= 1
        when 2
          return result.force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8)
        end

        if enlarge_in == 0
          enlarge_in = 2**num_bits
          num_bits += 1
        end

        entry =
          if dictionary[code]
            dictionary[code]
          elsif code == dictionary.size
            w + first_unit(units, w)
          else
            return nil
          end
        result << entry
        dictionary << (w + first_unit(units, entry))
        enlarge_in -= 1
        w = entry

        if enlarge_in == 0
          enlarge_in = 2**num_bits
          num_bits += 1
        end
      end
    rescue EncodingError
      nil
    end

    # Phrases are dictionary codes rather than strings: a phrase extended by a
    # code unit is looked up as (phrase << 16 | unit), so compressing
    # allocates no string per phrase.
    def compress(code_units, bits_per_char)
      writer = BitWriter.new(bits_per_char)
      singles = {}
      phrases = {}
      to_create = {}
      dict_size = 3
      enlarge_in = 2
      num_bits = 2
      w = nil
      w_unit = nil

      emit = lambda do
        if w_unit && to_create.delete(w_unit)
          if w_unit < 256
            writer.write(0, num_bits)
            writer.write(w_unit, 8)
          else
            writer.write(1, num_bits)
            writer.write(w_unit, 16)
          end
          enlarge_in -= 1
          if enlarge_in == 0
            enlarge_in = 2**num_bits
            num_bits += 1
          end
        else
          writer.write(w, num_bits)
        end
        enlarge_in -= 1
        if enlarge_in == 0
          enlarge_in = 2**num_bits
          num_bits += 1
        end
      end

      code_units.each do |c|
        unless singles.key?(c)
          singles[c] = dict_size
          dict_size += 1
          to_create[c] = true
        end

        if w.nil?
          w = singles[c]
          w_unit = c
        elsif (code = phrases[(w << 16) | c])
          w = code
          w_unit = nil
        else
          emit.call
          phrases[(w << 16) | c] = dict_size
          dict_size += 1
          w = singles[c]
          w_unit = c
        end
      end
      emit.call if w
      writer.write(2, num_bits)
      writer.finish
    end

    def unit(units, code)
      units[code] ||= [code].pack("n").freeze
    end

    # The first code unit of an entry, from the cache rather than byteslice,
    # so that extending an entry allocates only the result.
    def first_unit(units, entry)
      unit(units, (entry.getbyte(0) << 8) | entry.getbyte(1))
    end

    class BitWriter
      def initialize(bits_per_char)
        @bits_per_char = bits_per_char
        @val = 0
        @position = 0
        @out = +""
      end

      # Writes the low count bits of value, lowest first.
      def write(value, count)
        count.times do
          @val = (@val << 1) | (value & 1)
          if @position == @bits_per_char - 1
            @out << BASE64_ALPHABET.getbyte(@val)
            @val = 0
            @position = 0
          else
            @position += 1
          end
          value >>= 1
        end
      end

      def finish
        loop do
          @val <<= 1
          if @position == @bits_per_char - 1
            @out << BASE64_ALPHABET.getbyte(@val)
            return @out
          end
          @position += 1
        end
      end
    end

    class BitReader
      def initialize(values, reset_value)
        @values = values
        @reset_value = reset_value
        @val = values.fetch(0, 0)
        @position = reset_value
        @index = 1
      end

      def exhausted?
        @index > @values.size
      end

      def read(count)
        bits = 0
        count.times do |i|
          bit = @val & @position
          @position >>= 1
          if @position == 0
            @position = @reset_value
            @val = @values.fetch(@index, 0)
            @index += 1
          end
          bits |= 1 << i if bit > 0
        end
        bits
      end
    end
  end
end
