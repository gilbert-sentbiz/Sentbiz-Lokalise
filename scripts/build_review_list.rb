#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require_relative "review_support"

options = { "output_dir" => File.join(ReviewSupport::PROJECT_ROOT, "output") }

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/build_review_list.rb --figma-url URL"
  parser.on("--figma-url URL", "Figma node URL") { |value| options["figma_url"] = value }
  parser.on("--output-dir DIR", "Output directory") { |value| options["output_dir"] = value }
end.parse!

raise "Missing --figma-url" unless options["figma_url"]

review = ReviewSupport.build_review(options["figma_url"])
txt_path, json_path = ReviewSupport.write_review_outputs(review, options["output_dir"])

puts "Node: #{review['node_name']}"
puts "Unique texts: #{review['existing'].length + review['skip'].length + review['new'].length}"
puts "Existing: #{review['existing'].length}"
puts "Skip: #{review['skip'].length}"
puts "New: #{review['new'].length}"
puts "Text output: #{txt_path}"
puts "JSON output: #{json_path}"
