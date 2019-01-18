require "json"
require "rgb"  # Color calculation library, gem is named "rgb"

# Munin palette taken from Rickshaw code, lightly modified
MUNIN_PALETTE = [
  '#00cc00',
  '#0066b3',
  '#ff8000',
  '#808080',
  '#ff0000',
  '#008f00',
  '#330099',
  '#990099',
  '#ccff00',
  '#ffcc00',
  '#00487d',
  '#b35a00',
  '#b38f00',
  '#6b006b',
  '#8fb300',
  '#b30000',
  '#bebebe',
  '#80ff80',
  '#80c9ff',
  '#ffc080',
  '#ffe680',
  '#aa80ff',
  '#ee00cc',
  '#ff8080',
  '#666600',
  '#ffbfff',
  '#00ffcc',
  '#cc6699',
  '#999900'
];

# Interpolate in HSV color space between the start and end colors
def simple_gradient_palette(start_color_rgb_hex, end_color_rgb_hex, num_entries: 10)
  start_color = RGB::Color.from_rgb_hex(start_color_rgb_hex)
  end_color = RGB::Color.from_rgb_hex(end_color_rgb_hex)

  entries = []
  num_entries.times do |index|
    frac = index.to_f / (num_entries - 1.0)
    this_hue = start_color.h * (1 - frac) + end_color.h * frac
    this_saturation = start_color.s * (1 - frac) + end_color.s * frac
    this_lightness = start_color.l * (1 - frac) + end_color.l * frac
    entries.push RGB::Color.new(this_hue, this_saturation, this_lightness).to_rgb_hex
  end
  entries
end

def gradient_of_hue(base_color_rgb_hex, min_value, max_value, num_entries)
  entries = []
  increment = max_value - min_value / num_entries
  base_color = RGB::Color.from_rgb_hex(base_color_rgb_hex)

  (1..num_entries).map do |i|
    val = min_value + i * increment
    (base_color * val).to_rgb_hex
  end
end

def bluegreen_palette(num_entries)
  return [] if num_entries < 1
  return [ "#DCEDC8" ] if num_entries == 1
  return [ "#DCEDC8", "#1A237E" ] if num_entries == 2
  return [ "#DCEDC8", "#42B3D5", "#1A237E" ] if num_entries == 3

  # We'll always have the three hardcoded colors in any gradient of size 3 or greater.
  # We'll interpolated num_entries - 3 more colors, divided into two gradients.

  interpolated_entries = num_entries - 3
  first_interpolated_entries = interpolated_entries / 2
  second_interpolated_entries = interpolated_entries - first_interpolated_entries  # Either same as first, or one larger

  # To interpolate, add 2 (the first and last) to the number of interpolated colors in each gradient...
  # Then ignore the first element of the second gradient, because it will be the color #42B3D5 repeated.

  palette = simple_gradient_palette("#DCEDC8", "#42B3D5", num_entries: first_interpolated_entries + 2) +
    simple_gradient_palette("#42B3D5", "#1A237E", num_entries: second_interpolated_entries + 2)[1..-1]

  palette
end

def contrast_palette(num_entries)
  if num_entries > MUNIN_PALETTE.size
    raise "Too many color entries requested: #{num_entries.inspect}!"
  end
  MUNIN_PALETTE[0..(num_entries-1)]
end

# This isn't perfect - at some fixed number of entries it gives up and switches to a simple gradient palette.
# But for now, it'll do.
def some_palette(num_entries)
  return contrast_palette(num_entries) if num_entries <= MUNIN_PALETTE.size
  bluegreen_palette(num_entries)
end

# load_ab_csv returns 101 floating-point entries for the request time at that percentage - zero through 100.
def load_ab_csv(filename)
  contents = File.read filename
  lines = contents.split("\n")
  if lines[0] != "Percentage served,Time in ms"
    raise "Expected ApacheBench CSV file, but first line was: #{lines[0]}.inspect!"
  end
  if lines.size != 102
    raise "Expected full-length ApacheBench CSV w/ percentages, but got #{lines.size.inspect} lines instead of 102 lines!"
  end
  ms_timings = lines[1..-1].map { |line| line.split(",", 2)[1].to_f }
  ms_timings
end

# TODO: replace all this bespoke logic with descriptive_statistics gem

def percentile(list, pct)
  len = list.length
  how_far = pct * 0.01 * (len - 1)
  prev_item = how_far.to_i
  return list[prev_item] if prev_item >= len - 1
  return list[0] if prev_item < 0

  linear_combination = how_far - prev_item
  list[prev_item] + (list[prev_item + 1] - list[prev_item]) * linear_combination
end

def array_mean(arr)
  return nil if arr.empty?
  arr.inject(0.0, &:+) / arr.size
end

# Calculate variance based on the Wikipedia article of algorithms for variance.
# https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance
# Includes Bessel's correction.
def array_variance(arr)
  n = arr.size
  return nil if arr.empty? || n < 2

  ex = ex2 = 0
  arr.each do |x|
    diff = x - arr[0]
    ex += diff
    ex2 += diff * diff
  end

  (ex2 - (ex * ex) / arr.size) / (arr.size - 1)
end
