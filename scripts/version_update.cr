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

targets = [
  {
    file:        "shard.yml",
    pattern:     /(^version:\s*).+$/m,
    replacement: "\\1#{version}",
  },
  {
    file:        "src/mzap/version.cr",
    pattern:     /(VERSION\s*=\s*"v?)[\d.]+(")/,
    replacement: "\\1#{version}\\2",
  },
  {
    file:        "snap/snapcraft.yaml",
    pattern:     /(^version:\s*).+$/m,
    replacement: "\\1#{version}",
  },
]

targets.each do |target|
  file = target[:file]
  if File.exists?(file)
    content = File.read(file)
    updated = content.gsub(target[:pattern], target[:replacement])
    File.write(file, updated)
    puts "✓ Updated #{file}"
  else
    puts "⚠ #{file} not found, skipping"
  end
end

puts "\nVersion updated to #{version}"
puts "Run `just version-check` to verify"
