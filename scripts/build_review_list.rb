#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "optparse"
require "set"
require "uri"

PROJECT_ROOT = File.expand_path("..", __dir__)
SKILL_DIR = File.join(PROJECT_ROOT, "skills", "auto-translation")
LOCAL_SECRET_PATH = File.join(PROJECT_ROOT, ".codex", "lokalise.json")
GLOBAL_SECRET_PATH = File.expand_path("~/.codex/secrets/lokalise.json")
CLAUDE_SETTINGS_PATH = File.expand_path("~/.claude/settings.json")

REQUIRED_KEYS = %w[FIGMA_TOKEN LOKALISE_TOKEN LOKALISE_PROJECT_ID].freeze
OPTIONAL_KEYS = %w[GOOGLE_SHEETS_WEBHOOK].freeze

DEFAULT_TERM_MAP = {
  "월렛" => "Wallet",
  "고객사" => "Client",
  "고객" => "Client",
  "채널" => "Channel",
  "상점" => "Merchant",
  "거래" => "Transaction",
  "내역" => "History",
  "관리" => "Management",
  "번호" => "Number",
  "상태" => "Status",
  "취소" => "Cancellation",
  "거래상태" => "Transaction Status",
  "취소상태" => "Cancellation Status",
  "거래유형" => "Transaction Type",
  "계약타입" => "Contract Type",
  "계약상태" => "Contract Status",
  "계약시작일자" => "Contract Start Date",
  "계약종료일자" => "Contract End Date",
  "거래일자" => "Transaction Date",
  "고객사명" => "Client Name",
  "채널명" => "Channel Name",
  "상점명" => "Merchant Name",
  "고객사명(고객사ID)" => "Client Company Name (Client ID)",
  "채널명(채널ID)" => "Channel Name (Channel ID)",
  "상점명(상점ID)" => "Merchant Name (Merchant ID)",
  "월렛거래번호" => "Wallet Transaction Number",
  "월렛 거래번호" => "Wallet Transaction Number",
  "월렛ID" => "Wallet ID",
  "월렛 ID" => "Wallet ID",
  "서비스수단" => "Service Method",
  "기준통화" => "Base Currency",
  "엑셀 다운로드" => "Download Excel File",
  "조회" => "Search",
  "검색" => "Search",
  "전체" => "All",
  "총" => "Total",
  "개" => "Items",
  "등록일시" => "Created At",
  "등록자" => "Created By",
  "수정일시" => "Updated At",
  "수정자" => "Updated By",
  "수정완료" => "Edit Complete",
  "닫기" => "Close",
  "대기" => "Pending",
  "비활성" => "Inactive",
  "중지" => "Suspend",
  "메모" => "Memo",
  "정보" => "Information",
  "생성" => "Create",
  "ID" => "ID",
  "일자" => "Date",
  "타입" => "Type",
  "수단" => "Method",
  "영어" => "English",
  "한국어" => "Korean",
  "월렛생성" => "Create Wallet"
}.freeze

ACRONYMS = Set.new(%w[ID MID API UI URL BO]).freeze

def deep_find_key(object, key)
  case object
  when Hash
    return object[key] if object.key?(key)

    object.each_value do |value|
      found = deep_find_key(value, key)
      return found if found
    end
  when Array
    object.each do |value|
      found = deep_find_key(value, key)
      return found if found
    end
  end
  nil
end

def load_json_if_exists(path)
  return nil unless File.exist?(path)

  JSON.parse(File.read(path))
end

def load_secrets
  sources = []
  sources << load_json_if_exists(LOCAL_SECRET_PATH)
  sources << load_json_if_exists(GLOBAL_SECRET_PATH)
  sources << ENV.to_h
  sources << load_json_if_exists(CLAUDE_SETTINGS_PATH)

  merged = {}
  (REQUIRED_KEYS + OPTIONAL_KEYS).each do |key|
    sources.each do |source|
      next unless source

      value = deep_find_key(source, key)
      next if value.nil? || value.to_s.strip.empty?

      merged[key] = value.to_s
      break
    end
  end

  missing = REQUIRED_KEYS.reject { |key| merged[key] && !merged[key].empty? }
  raise "Missing required credentials: #{missing.join(', ')}" unless missing.empty?

  merged
end

def parse_table_mappings(path)
  mappings = {}
  return mappings unless File.exist?(path)

  File.readlines(path, chomp: true).each do |line|
    next unless line.start_with?("|")

    cells = line.split("|").map(&:strip).reject(&:empty?)
    next unless cells.length >= 2
    next if cells[0] == "한글" || cells[0] == "날짜" || cells[0].match?(/\A-+\z/)

    mappings[cells[0]] = cells[1]
  end

  mappings
end

def request_json(url, headers)
  uri = URI(url)
  req = Net::HTTP::Get.new(uri)
  headers.each { |key, value| req[key] = value }

  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 60) do |http|
    res = http.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      body = res.body.to_s[0, 500]
      raise "HTTP #{res.code} for #{url}: #{body}"
    end

    [JSON.parse(res.body), res]
  end
end

def parse_figma_url(figma_url)
  uri = URI(figma_url)
  file_key = uri.path.split("/")[2]
  params = URI.decode_www_form(uri.query.to_s).to_h
  node_id = params["node-id"]&.tr("-", ":")
  raise "Figma URL must include node-id" if file_key.nil? || node_id.nil? || node_id.empty?

  { "file_key" => file_key, "node_id" => node_id }
end

def extract_unique_texts(figma_payload)
  root = figma_payload.fetch("nodes").values.first.fetch("document")
  texts = []

  walk = lambda do |node|
    if node["type"] == "TEXT"
      text = node["characters"].to_s.strip
      texts << text unless text.empty?
    end
    node.fetch("children", []).each { |child| walk.call(child) }
  end

  walk.call(root)

  seen = Set.new
  unique = texts.reject { |text| seen.include?(text) || (seen << text; false) }
  [root["name"], unique]
end

def fetch_lokalise_keys(secret)
  keys = []
  page = 1

  loop do
    query = URI.encode_www_form("limit" => 500, "page" => page, "include_translations" => 1)
    url = "https://api.lokalise.com/api2/projects/#{secret.fetch('LOKALISE_PROJECT_ID')}/keys?#{query}"
    payload, res = request_json(url, "x-api-token" => secret.fetch("LOKALISE_TOKEN"))
    keys.concat(payload.fetch("keys", []))
    page_count = res["x-pagination-page-count"].to_i
    break if page >= page_count

    page += 1
  end

  keys
end

def build_existing_map(keys)
  existing = {}

  keys.each do |entry|
    ko = entry.fetch("translations", []).find { |t| t["language_iso"] == "ko" }.to_h["translation"].to_s.strip
    en = entry.fetch("translations", []).find { |t| t["language_iso"] == "en" }.to_h["translation"].to_s.strip
    next if ko.empty?

    existing[ko] ||= {
      "key" => (entry.dig("key_name", "web") || entry["key_name"].to_s),
      "en" => en
    }
  end

  existing
end

def has_hangul?(text)
  text.each_char.any? { |char| char.ord.between?(0xAC00, 0xD7A3) }
end

def build_term_map
  glossary = parse_table_mappings(File.join(SKILL_DIR, "domain-glossary.md"))
  corrections = parse_table_mappings(File.join(SKILL_DIR, "user-corrections.md"))
  DEFAULT_TERM_MAP.merge(glossary).merge(corrections)
end

def translate_phrase(text, term_map)
  return term_map[text] if term_map[text]

  pieces = []
  remaining = text.dup
  sorted_terms = term_map.keys.sort_by { |item| -item.length }

  until remaining.empty?
    if remaining =~ /\A\s+/
      remaining = Regexp.last_match.post_match
      next
    end

    match = sorted_terms.find { |term| remaining.start_with?(term) }
    if match
      pieces << term_map[match]
      remaining = remaining[match.length..]
      next
    end

    if remaining =~ /\A[\(\)\/,:_-]/
      pieces << Regexp.last_match[0]
      remaining = Regexp.last_match.post_match
      next
    end

    if remaining =~ /\A[0-9A-Za-z]+/
      pieces << Regexp.last_match[0]
      remaining = Regexp.last_match.post_match
      next
    end

    if remaining =~ /\A./m
      pieces << Regexp.last_match[0]
      remaining = Regexp.last_match.post_match
    end
  end

  english = pieces.join(" ")
                  .gsub(/\s+([\/,:_\-\)])/, '\1')
                  .gsub(/([\(\-])\s+/, '\1')
                  .gsub(/\s+/, " ")
                  .strip

  words = english.split
  if words.length > 1 && words.last == "Create"
    words = [words.last] + words[0...-1]
    english = words.join(" ")
  end

  english
end

def classify_prefix(text)
  return "msgPlaceholder_" if text.include?("입력") || text.include?("선택") || text.include?("검색어를 입력")
  return "msgError_" if text.include?("실패") || text.include?("오류")
  return "msgTooltip_" if text.include?("도움말") || text.include?("툴팁")

  "common_"
end

def to_pascal_case(english)
  tokens = english.scan(/[A-Za-z0-9]+/)
  return "ManualReview" if tokens.empty?

  tokens.map do |token|
    up = token.upcase
    if ACRONYMS.include?(up)
      up
    elsif token.match?(/\A\d+\z/)
      token
    else
      token[0].upcase + token[1..].to_s.downcase
    end
  end.join
end

def build_key_proposal(text, english)
  prefix = classify_prefix(text)
  "#{prefix}#{to_pascal_case(english)}"
end

def fit(text, width)
  plain = text.to_s.gsub(/\s+/, " ").strip
  return plain.ljust(width) if plain.length <= width

  plain[0, width - 3] + "..."
end

def render_section(title, rows)
  output = []
  output << title
  output << ""
  output << "```text"
  output << [
    fit("No", 3),
    fit("국문", 20),
    fit("영문 번역 제안", 24),
    fit("키 제안", 48),
    "상태"
  ].join("  ")

  rows.each_with_index do |row, index|
    output << [
      fit(format("%02d", index + 1), 3),
      fit(row["ko"], 20),
      fit(row["en"].empty? ? "-" : row["en"], 24),
      fit(row["key"], 48),
      row["status"]
    ].join("  ")
  end

  output << "```"
  output << ""
  output.join("\n")
end

def sanitize_slug(text)
  text.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
end

options = {
  "output_dir" => File.join(PROJECT_ROOT, "output")
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/build_review_list.rb --figma-url URL"
  parser.on("--figma-url URL", "Figma node URL") { |value| options["figma_url"] = value }
  parser.on("--output-dir DIR", "Output directory") { |value| options["output_dir"] = value }
end.parse!

raise "Missing --figma-url" unless options["figma_url"]

secret = load_secrets
figma_ref = parse_figma_url(options["figma_url"])
term_map = build_term_map
skip_data = load_json_if_exists(File.join(SKILL_DIR, "skip-list.json")) || {}
skip_exact = Set.new(skip_data.fetch("exact", []))
skip_patterns = skip_data.fetch("patterns", []).map { |item| Regexp.new(item) }

figma_url = "https://api.figma.com/v1/files/#{figma_ref.fetch('file_key')}/nodes?ids=#{URI.encode_www_form_component(figma_ref.fetch('node_id'))}"
figma_payload, = request_json(figma_url, "X-Figma-Token" => secret.fetch("FIGMA_TOKEN"))
node_name, unique_texts = extract_unique_texts(figma_payload)

existing_map = build_existing_map(fetch_lokalise_keys(secret))

existing_rows = []
skip_rows = []
new_rows = []

unique_texts.each do |text|
  if existing_map[text]
    existing_rows << {
      "ko" => text,
      "en" => existing_map[text]["en"],
      "key" => existing_map[text]["key"],
      "status" => "기존 키 후보"
    }
  elsif skip_exact.include?(text) || skip_patterns.any? { |pattern| pattern.match?(text) } || !has_hangul?(text)
    skip_rows << {
      "ko" => text,
      "en" => "",
      "key" => "skip",
      "status" => "스킵 후보"
    }
  else
    english = translate_phrase(text, term_map)
    new_rows << {
      "ko" => text,
      "en" => english,
      "key" => build_key_proposal(text, english),
      "status" => "신규 키 후보"
    }
  end
end

FileUtils.mkdir_p(options["output_dir"])
slug = sanitize_slug(node_name.empty? ? "review" : node_name)
txt_path = File.join(options["output_dir"], "#{slug}-review.txt")
json_path = File.join(options["output_dir"], "#{slug}-review.json")

sections = []
sections << render_section("기존 키 1-#{existing_rows.length}", existing_rows)
sections << render_section("스킵 1-#{skip_rows.length}", skip_rows)
sections << render_section("신규 키 1-#{new_rows.length}", new_rows)

File.write(txt_path, sections.join("\n"))
File.write(json_path, JSON.pretty_generate({
  "figma_url" => options["figma_url"],
  "node_name" => node_name,
  "counts" => {
    "existing" => existing_rows.length,
    "skip" => skip_rows.length,
    "new" => new_rows.length
  },
  "existing" => existing_rows,
  "skip" => skip_rows,
  "new" => new_rows
}) + "\n")

puts "Node: #{node_name}"
puts "Unique texts: #{unique_texts.length}"
puts "Existing: #{existing_rows.length}"
puts "Skip: #{skip_rows.length}"
puts "New: #{new_rows.length}"
puts "Text output: #{txt_path}"
puts "JSON output: #{json_path}"
