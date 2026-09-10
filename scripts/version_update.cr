version = ARGV[0]?

unless version
  print "Enter new version (e.g. 2.1.1): "
  version = gets.try(&.strip)
end

if version.nil? || version.empty?
  puts "No version provided"
  exit 1
end

version = version.lstrip('v')

# NOTE: Crystal's `m` flag turns on both MULTILINE and DOTALL, so `.` matches
# newlines as well. Line-oriented patterns must use `[^\n]` instead of `.`,
# otherwise the match runs to the end of the file and truncates it.
targets = [
  {
    file:    "shard.yml",
    pattern: /(^version:[ \t]*)[^\n]+/m,
  },
  {
    file:    "src/mzap/version.cr",
    pattern: /(VERSION\s*=\s*"v?)[\d.]+(")/,
  },
  {
    file:    "snap/snapcraft.yaml",
    pattern: /(^version:[ \t]*)[^\n]+/m,
  },
]

targets.each do |target|
  file = target[:file]

  unless File.exists?(file)
    puts "⚠ #{file} not found, skipping"
    next
  end

  content = File.read(file)

  unless content.matches?(target[:pattern])
    puts "⚠ #{file} has no version line to update"
    next
  end

  updated = content.gsub(target[:pattern]) { |_, match| "#{match[1]}#{version}#{match[2]?}" }

  if updated == content
    puts "= #{file} already at #{version}"
    next
  end

  File.write(file, updated)
  puts "✓ Updated #{file}"
end

puts "\nVersion updated to #{version}"
puts "Run `just version-check` to verify"
