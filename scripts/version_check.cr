files = {
  "shard.yml"            => /^version:\s*(.+)$/,
  "src/mzap/version.cr"  => /VERSION\s*=\s*"v?(.+?)"/,
  "snap/snapcraft.yaml"  => /^version:\s*(.+)$/,
}

versions = {} of String => String

files.each do |file, pattern|
  if File.exists?(file)
    File.each_line(file) do |line|
      if m = line.match(pattern)
        versions[file] = m[1]
        break
      end
    end
  else
    puts "⚠ #{file} not found"
  end
end

puts "Version check:"
versions.each do |file, version|
  puts "  #{file}: #{version}"
end

unique = versions.values.uniq
if unique.size == 1
  puts "\n✓ All versions match (#{unique.first})"
else
  puts "\n✗ Version mismatch detected!"
  exit 1
end
