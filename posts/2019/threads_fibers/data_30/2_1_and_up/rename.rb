#!/usr/bin/env ruby

require "fileutils"

Dir["*_ruby-head_*"].each do |filename|
  new_filename = filename.gsub("_ruby-head_", "_2.7_")
  STDERR.puts "Move: #{filename.inspect} #{new_filename.inspect}"
  FileUtils.mv filename, new_filename
end
