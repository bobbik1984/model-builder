require 'zlib'

module ModelBuilder
  # Minimal raster drawing so the export can burn markup into a screenshot.
  # SketchUp's view.write_image does NOT include overlay/tool drawing (verified
  # 2026-11-08), so we draw ourselves: read the BMP SketchUp writes, draw
  # lines/discs/labels, and encode a PNG (stdlib zlib only, no gems).
  class Raster
    attr_reader :width, :height

    # 5x7 bitmap font for labels (digits, a few capitals).
    FONT = {
      '0' => %w[01110 10001 10011 10101 11001 10001 01110], '1' => %w[00100 01100 00100 00100 00100 00100 01110],
      '2' => %w[01110 10001 00001 00010 00100 01000 11111], '3' => %w[11110 00001 00001 01110 00001 00001 11110],
      '4' => %w[00010 00110 01010 10010 11111 00010 00010], '5' => %w[11111 10000 11110 00001 00001 10001 01110],
      '6' => %w[00110 01000 10000 11110 10001 10001 01110], '7' => %w[11111 00001 00010 00100 01000 01000 01000],
      '8' => %w[01110 10001 10001 01110 10001 10001 01110], '9' => %w[01110 10001 10001 01111 00001 00010 01100],
      'S' => %w[01111 10000 10000 01110 00001 00001 11110], 'P' => %w[11110 10001 10001 11110 10000 10000 10000],
      'R' => %w[11110 10001 10001 11110 10100 10010 10001]
    }.freeze unless defined?(FONT)

    def self.from_bmp(path)
      data = File.binread(path)
      raise "Not a BMP: #{path}" unless data[0, 2] == 'BM'

      offset = data[10, 4].unpack1('V')
      w = data[18, 4].unpack1('l<')
      h = data[22, 4].unpack1('l<')
      bpp = data[28, 2].unpack1('v')
      raise "Unsupported BMP bit depth #{bpp}" unless [24, 32].include?(bpp)

      top_down = h.negative?
      h = h.abs
      bytes = bpp / 8
      stride = ((w * bytes + 3) / 4) * 4
      rgb = String.new(capacity: w * h * 3, encoding: Encoding::BINARY)
      h.times do |row|
        src_row = top_down ? row : h - 1 - row
        vals = data.byteslice(offset + src_row * stride, w * bytes).unpack('C*')
        # BGR(A) -> RGB
        rgb << vals.each_slice(bytes).flat_map { |px| [px[2], px[1], px[0]] }.pack('C*')
      end
      new(w, h, rgb)
    end

    # Load any image SketchUp can read (PNG, JPG, ...) downscaled so its longest
    # side is at most max_side px (nearest-neighbour; it is a preview).
    # Returns [raster, original_width, original_height].
    def self.load_scaled(path, max_side)
      rep = Sketchup::ImageRep.new
      rep.load_file(path)
      w = rep.width
      h = rep.height
      bytes = rep.bits_per_pixel / 8
      raise "Unsupported image depth #{rep.bits_per_pixel}" unless [3, 4].include?(bytes)

      data = rep.data
      stride = w * bytes + rep.row_padding
      scale = [w, h].max > max_side ? max_side.to_f / [w, h].max : 1.0
      nw = [(w * scale).round, 1].max
      nh = [(h * scale).round, 1].max
      xs = (0...nw).map { |x| [(x / scale).floor, w - 1].min * bytes }
      rgb = String.new(capacity: nw * nh * 3, encoding: Encoding::BINARY)
      nh.times do |y|
        sy = [(y / scale).floor, h - 1].min
        # ImageRep rows are top-down, pixels BGR(A) (verified 2026-11-08 with a
        # synthetic red-top/blue-bottom image, dev/markup_test.rb).
        vals = data.byteslice(sy * stride, w * bytes).unpack('C*')
        rgb << xs.flat_map { |o| [vals[o + 2], vals[o + 1], vals[o]] }.pack('C*')
      end
      [new(nw, nh, rgb), w, h]
    end

    def initialize(width, height, rgb)
      @width = width
      @height = height
      @rgb = rgb
    end

    def get(x, y)
      i = (y * @width + x) * 3
      [@rgb.getbyte(i), @rgb.getbyte(i + 1), @rgb.getbyte(i + 2)]
    end

    def set(x, y, color, alpha = 1.0)
      return if x.negative? || y.negative? || x >= @width || y >= @height

      i = (y * @width + x) * 3
      3.times do |c|
        v = alpha >= 1.0 ? color[c] : (color[c] * alpha + @rgb.getbyte(i + c) * (1 - alpha)).round
        @rgb.setbyte(i + c, v)
      end
    end

    def disc(cx, cy, r, color, alpha = 1.0)
      r2 = r * r
      (-r.ceil..r.ceil).each do |dy|
        (-r.ceil..r.ceil).each do |dx|
          set((cx + dx).round, (cy + dy).round, color, alpha) if dx * dx + dy * dy <= r2
        end
      end
    end

    def ring(cx, cy, r, width, color)
      outer = r * r
      inner = (r - width)**2
      (-r.ceil..r.ceil).each do |dy|
        (-r.ceil..r.ceil).each do |dx|
          d = dx * dx + dy * dy
          set((cx + dx).round, (cy + dy).round, color) if d <= outer && d >= inner
        end
      end
    end

    def line(x0, y0, x1, y1, width, color)
      len = Math.hypot(x1 - x0, y1 - y0)
      steps = [len.ceil, 1].max
      rad = width / 2.0
      (0..steps).each do |s|
        t = s.to_f / steps
        disc(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, rad, color)
      end
    end

    # Dashed line: on/off pieces of dash px, for marks hidden behind geometry.
    def dashed_line(x0, y0, x1, y1, width, color, dash = 10)
      len = Math.hypot(x1 - x0, y1 - y0)
      return if len.zero?

      steps = len.ceil
      rad = width / 2.0
      (0..steps).each do |st|
        next if (st / dash).odd?

        t = st.to_f / steps
        disc(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, rad, color)
      end
    end

    def rect(x, y, w, h, color)
      h.times { |dy| w.times { |dx| set(x + dx, y + dy, color) } }
    end

    # Text with the 5x7 font, top-left at (x, y), each font pixel = scale px.
    def text(x, y, str, color, scale = 2)
      str.each_char.with_index do |ch, k|
        glyph = FONT[ch.upcase] or next
        glyph.each_with_index do |row, gy|
          row.each_char.with_index do |bit, gx|
            next unless bit == '1'

            rect(x.round + (k * 6 + gx) * scale, y.round + gy * scale, scale, scale, color)
          end
        end
      end
    end

    def self.text_size(str, scale = 2)
      [(str.length * 6 - 1) * scale, 7 * scale]
    end

    def write_png(path)
      raw = String.new(capacity: (@width * 3 + 1) * @height, encoding: Encoding::BINARY)
      row_bytes = @width * 3
      @height.times do |y|
        raw << "\x00".b << @rgb.byteslice(y * row_bytes, row_bytes)
      end
      chunk = lambda do |type, body|
        [body.bytesize].pack('N') + type + body + [Zlib.crc32(type + body)].pack('N')
      end
      png = "\x89PNG\r\n\x1a\n".b
      png << chunk.('IHDR', [@width, @height, 8, 2, 0, 0, 0].pack('NNCCCCC'))
      png << chunk.('IDAT', Zlib::Deflate.deflate(raw, 6))
      png << chunk.('IEND', ''.b)
      File.binwrite(path, png)
    end
  end
end
