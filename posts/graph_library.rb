require "json"
require "rgb"  # Color calculation library, gem is named "rgb"

# Munin palette taken from Rickshaw code
MUNIN_PALETTE = [
  '#00cc00',
  '#0066b3',
  '#ff8000',
  '#ffcc00',
  '#330099',
  '#990099',
  '#ccff00',
  '#ff0000',
  '#808080',
  '#008f00',
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

