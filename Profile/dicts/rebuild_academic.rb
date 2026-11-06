#!/usr/bin/ruby
# Apply subject selection to native imports and rebuild ordinary mixed spellings.
require 'yaml'
require 'tempfile'

profile = File.expand_path('..', __dir__)
academic = File.join(__dir__, 'academic_dicts')
settings = YAML.safe_load(File.read(File.join(academic, 'subjects.yaml')))
subjects = settings.fetch('subjects')
raise 'subjects must map subject names to true or false' unless subjects.is_a?(Hash)
subjects.each do |name, enabled|
  unless name.is_a?(String) && name.match?(/\A[a-z][a-z0-9_]*\z/) && !name.end_with?('_mixed') && [true, false].include?(enabled)
    raise "Invalid subject setting: #{name.inspect} => #{enabled.inspect}"
  end
  raise "Missing subject dictionary: #{name}" unless File.file?(File.join(academic, "#{name}.dict.yaml"))
end
Dir.glob(File.join(academic, '*.dict.yaml')).each do |file|
  name = File.basename(file, '.dict.yaml').sub(/_mixed\z/, '')
  raise "Subject #{name} must be listed in subjects.yaml" unless subjects.key?(name)
end
active = subjects.select { |_, enabled| enabled }.keys
chinese = active.map { |name| "dicts/academic_dicts/#{name}" }
mixed = active.map do |name|
  "dicts/academic_dicts/#{name}_mixed" if File.file?(File.join(academic, "#{name}_mixed.dict.yaml"))
end.compact

def imports_text(path, tables)
  old = File.read(path)
  pattern = /^  # BEGIN ACADEMIC SUBJECTS\n.*?^  # END ACADEMIC SUBJECTS\n/m
  raise "Missing or repeated academic import block in #{path}" unless old.scan(pattern).size == 1
  block = ["  # BEGIN ACADEMIC SUBJECTS", *tables.map { |name| "  - #{name}" }, "  # END ACADEMIC SUBJECTS"].join("\n") + "\n"
  old.sub(pattern, block)
end

main_path = File.join(profile, 'zenfire_pinyin.dict.yaml')
mixed_path = File.join(profile, 'extended_mixed.dict.yaml')
main_text = imports_text(main_path, chinese)
mixed_text = imports_text(mixed_path, mixed)
header = mixed_text.partition(/^\.\.\.\r?\n/).first
sources = YAML.safe_load(header).fetch('import_tables').map do |name|
  File.join(profile, "#{name}.dict.yaml")
end
target = File.join(__dir__, 'cn_dicts/personal_mixed.txt')
scheme = File.expand_path('../zenfire_pinyin_fuzzy.yaml', __dir__)
config = YAML.safe_load(File.read(scheme))
rules = config.fetch('personal_fuzzy').fetch('__append').map do |rule|
  fields = %r{\Aderive/([^/]+)/([^/]*)/\z}.match(rule) or raise "Unsupported spelling rule: #{rule}"
  replacement = fields[2].gsub(/\$(\d+)/) { '\\' + Regexp.last_match(1) }
  [Regexp.new(fields[1]), replacement]
end

def spellings(part, code, rules)
  if part.match?(/\A[a-z]+\z/i)
    raise "Latin spelling mismatch: #{part} / #{code}" unless part.downcase == code
    return [code]
  end
  raise "Unsupported written token: #{part}" unless part.match?(/\A[\p{Han}0-9ⅠⅡ]\z/)
  rules.reduce([code]) do |forms, (pattern, replacement)|
    (forms + forms.map { |s| s.sub(pattern, replacement) }).uniq
  end
end

exact = {}
aliases = {}
readings = Hash.new { |h, word| h[word] = [] }
sources.each do |source|
  body = File.read(source).partition(/^\.\.\.\r?\n/).last
  body.each_line do |line|
    next if line.strip.empty? || line.start_with?('#')
    word, reading, = line.chomp.split("\t")
    parts = word.scan(/[A-Za-z]+|\p{Han}|[^\s]/) - %w[. - ·]
    syllables = reading.split
    unless parts.length == syllables.length && syllables.all? { |s| s.match?(/\A[a-z]+\z/) }
      raise "Cannot align #{word} with #{reading}"
    end
    canonical = syllables.join
    exact[[word, canonical]] = 1
    forms = parts.zip(syllables).map { |part, syllable| spellings(part, syllable, rules) }
    forms.first.product(*forms.drop(1)).each do |tokens|
      code = tokens.join
      aliases[[word, code]] = 1 unless code == canonical
      readings[word] << tokens.join("'")
    end
  end
end
raise 'Mixed dictionary has no entries' if exact.empty?
exact.each_key { |pair| aliases.delete(pair) }
fuzzy_codes = aliases.keys.map(&:last).to_h { |s| [s, true] }
exact.each_key { |pair| exact[pair] = 2 if fuzzy_codes[pair.last] }

marker = '# Personal entries below this line are preserved when rebuilding.'
old = File.exist?(target) ? File.read(target) : ''
personal = if old.lines.any? { |l| l.chomp == marker }
             old.partition(/^#{Regexp.escape(marker)}\r?(?:\n|\z)/).last
           else
             # Migrate pre-generator tables without losing manually listed spellings or weights.
             old.lines.reject { |l| l.start_with?('#') || l.strip.empty? }.reject do |l|
               word, code, weight = l.chomp.split("\t")
               weight == '1' && (exact.key?([word, code]) || aliases.key?([word, code]))
             end.join
           end
personal.each_line do |line|
  next if line.strip.empty? || line.start_with?('#')
  row = /\A([^\t]+)\t([a-z]+)\t(\d+)\z/.match(line.chomp) or raise "Invalid personal entry: #{line.chomp}"
  exact.delete([row[1], row[2]])
  aliases.delete([row[1], row[2]])
end

lines = ['# Rime table', '# coding: utf-8', "#@/db_name\tpersonal_mixed.txt", "#@/db_type\ttabledb",
         '# Generated by dicts/rebuild_academic.rb from subjects.yaml, mixed imports and zenfire_pinyin_fuzzy.yaml.']
# Sort for editing while retaining source order for equal spellings.
ordered = (exact.to_a + aliases.to_a).each_with_index.sort_by do |(pair, _weight), index|
  [pair.last, index]
end
ordered.each { |(pair, weight), _index| lines << (pair + [weight]).join("\t") }
lines << ''
readings.sort_by { |_word, forms| forms.first }.each do |word, forms|
  lines << (['# syllables', word] + forms.uniq).join("\t")
end
text = (lines + ['', marker]).join("\n") + "\n" + personal
# Validate and compute all outputs before replacing any deployed source files.
outputs = {main_path => main_text, mixed_path => mixed_text, target => text}
staged = []
begin
  outputs.each do |path, content|
    next if File.exist?(path) && File.read(path) == content
    tmp = Tempfile.new(['.academic-', '.tmp'], File.dirname(path))
    staged << [tmp, path]
    tmp.chmod(File.stat(path).mode & 0o777) if File.exist?(path)
    tmp.write(content)
    tmp.close
  end
  staged.each { |tmp, path| File.rename(tmp.path, path) }
ensure
  staged.each { |tmp, _| tmp.close! }
end
puts "Enabled academic subjects: #{active.empty? ? '(none)' : active.join(', ')}. Choose Deploy to apply."
