#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "review_support"

VALID_DECISIONS = %w[approve reuse create skip].freeze

def normalize_section(rows, fallback)
  rows.map do |row|
    item = row.dup
    item["decision"] = item["decision"].to_s.strip
    item["decision"] = fallback if item["decision"].empty?
    item["note"] = item["note"].to_s
    item
  end
end

def validate_decisions!(review)
  ReviewSupport::SECTION_ORDER.each do |section|
    review.fetch(section).each_with_index do |row, index|
      decision = row["decision"].to_s
      next if VALID_DECISIONS.include?(decision)
      raise "Invalid decision for #{section} ##{index + 1}: #{decision.inspect}"
    end
  end
end

options = {}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/apply_review.rb --review-json output/xxx-review.json"
  parser.on("--review-json PATH", "Edited review JSON path") { |value| options["review_json"] = value }
end.parse!

raise "Missing --review-json" unless options["review_json"]

review = JSON.parse(File.read(options["review_json"]))
review["existing"] = normalize_section(review.fetch("existing"), "reuse")
review["skip"] = normalize_section(review.fetch("skip"), "skip")
review["new"] = normalize_section(review.fetch("new"), "create")

validate_decisions!(review)

approved_existing = review["existing"].select { |row| row["decision"] == "approve" || row["decision"] == "reuse" }
approved_new = review["new"].select { |row| row["decision"] == "approve" || row["decision"] == "create" }
skipped = review["existing"].select { |row| row["decision"] == "skip" } +
          review["skip"].select { |row| row["decision"] == "skip" } +
          review["new"].select { |row| row["decision"] == "skip" }

payload = {
  "figma_url" => review["figma_url"],
  "node_name" => review["node_name"],
  "reuse" => approved_existing.map { |row| row.slice("ko", "en", "key", "note", "decision") },
  "create" => approved_new.map { |row| row.slice("ko", "en", "key", "note", "decision") },
  "skip" => skipped.map { |row| row.slice("ko", "en", "key", "note", "decision") }
}

base = options["review_json"].sub(/-review\.json\z/, "")
summary_path = "#{base}-applied.txt"
json_path = "#{base}-applied.json"

summary = []
summary << "Node: #{review['node_name']}"
summary << "Reuse: #{payload['reuse'].length}"
summary << "Create: #{payload['create'].length}"
summary << "Skip: #{payload['skip'].length}"
summary << ""
summary << ReviewSupport.summarize_review(review)

File.write(summary_path, summary.join("\n"))
File.write(json_path, JSON.pretty_generate(payload) + "\n")

puts "Applied review: #{options['review_json']}"
puts "Summary output: #{summary_path}"
puts "JSON output: #{json_path}"
