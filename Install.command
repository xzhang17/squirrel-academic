#!/usr/bin/ruby
# Install the release profile into the signed-in macOS account.
require 'fileutils'
require 'tmpdir'

File.umask(0077)
root = File.expand_path(__dir__)
home = Dir.home
library = File.join(home, 'Library')
live = File.join(library, 'Rime')
app = '/Library/Input Methods/Squirrel.app'
local_app = File.join(library, 'Input Methods/Squirrel.app')
abort 'Run this as your own Mac account, without sudo.' if Process.uid.zero?
abort 'Install the official Squirrel input method first.' unless [app, local_app].any? { |p| File.executable?(File.join(p, 'Contents/MacOS/Squirrel')) }
abort 'The Rime folder is a link or is not a directory. Use Prepare-profile.command for a manual installation.' if File.symlink?(live) || (File.exist?(live) && !File.directory?(live))

puts 'Squirrel Academic Config · 学术拼音'
puts 'This installs the academic scheme, its dictionaries, local learning, punctuation settings and MacGreen skin.'
puts 'Only the academic scheme will be selected by the new configuration.'
puts 'Private phrase lists, learned choices, existing sync settings and unrelated files are preserved.'
print "Continue? [y/N] "
STDOUT.flush
exit 0 unless STDIN.gets.to_s.strip.match?(/\A(y|yes)\z/i)

File.open(library, File::RDONLY) do |lock|
  abort 'Another profile installation is running. Try again when it finishes.' unless lock.flock(File::LOCK_EX | File::LOCK_NB)
  Dir.mktmpdir('.squirrel-academic-install-', library) do |work|
    result = IO.popen(['/bin/bash', File.join(root, 'Prepare-profile.command'), work], &:read)
    abort 'Could not prepare the academic profile.' unless $?.success?
    staged = result.strip
    abort 'Unexpected prepared profile location.' unless File.dirname(staged) == work && File.directory?(staged)
    unless File.directory?(live)
      File.rename(staged, live)
      next
    end

    files = Dir.chdir(staged) { Dir.glob('**/*').select { |name| File.file?(name) } }
    protected_names = %w[custom_phrase.txt academic_preferences.txt installation.yaml]
    # Keep a migrated preferences file and preserve the user's text-icon setting.
    if File.exist?(File.join(live, 'academic_preferences.tsv'))
      files.delete('academic_preferences.txt')
    end
    skin = 'squirrel.custom.yaml'
    old_skin = File.join(live, skin)
    if File.file?(old_skin) && !File.symlink?(old_skin) && File.readlines(old_skin).any? { |line| line.chomp == '  status_icon/show: false' }
      file = File.join(staged, skin)
      File.write(file, File.read(file).sub('  status_icon/show: true', '  status_icon/show: false'))
    end

    changes = files.reject do |name|
      dest = File.join(live, name)
      next true if protected_names.include?(name) && (File.exist?(dest) || File.symlink?(dest))
      parts = name.split('/')
      path = live
      parts.each_with_index do |part, idx|
        path = File.join(path, part)
        abort "Linked or incompatible profile path: #{path}. Use Prepare-profile.command instead." if
          File.symlink?(path) || (File.exist?(path) && !(idx == parts.size - 1 ? File.file?(path) : File.directory?(path)))
      end
      File.file?(dest) && FileUtils.compare_file(File.join(staged, name), dest)
    end
    next if changes.empty?
    previous = Dir.mktmpdir('Squirrel-Academic-Previous-', library)
    replaced, added = changes.partition { |name| File.exist?(File.join(live, name)) }
    # Deploy can prune old pins when the release changes the eligible vocabulary.
    pins = 'academic_preferences.txt'
    saved = replaced.dup
    saved << pins if File.file?(File.join(live, pins)) && !File.symlink?(File.join(live, pins))
    saved.each do |name|
      path = File.join(previous, name)
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.copy_file(File.join(live, name), path, true)
    end
    File.write(File.join(previous, 'Added-files.txt'), added.map { |name| name + "\n" }.join)
    puts "Previous configuration files: #{previous}"
    installed = []
    begin
      changes.each do |name|
        dest = File.join(live, name)
        FileUtils.mkdir_p(File.dirname(dest))
        File.rename(File.join(staged, name), dest)
        installed << name
      end
    rescue StandardError, Interrupt
      installed.reverse_each do |name|
        dest = File.join(live, name)
        if replaced.include?(name)
          FileUtils.copy_file(File.join(previous, name), dest, true)
        else
          File.unlink(dest)
        end
      end
      raise
    end
  end
end

puts 'Profile installed. Choose Squirrel → Deploy (重新部署), switch to Chinese, and try mdjz → 密度矩阵.'
puts 'For smart spacing on the matching d220b92 nightly, run:'
puts '/bin/bash "$HOME/Library/Rime/native_typing/Install.command"'
system_binary = File.join(app, 'Contents/MacOS/Squirrel')
if File.file?(system_binary) && File.binread(system_binary).include?('SquirrelGetASCIIModeNotification')
  print "Install the optional clickable Chinese/English menu-bar indicator for this account? [y/N] "
  STDOUT.flush
  if STDIN.gets.to_s.strip.match?(/\A(y|yes)\z/i)
    ok = system('/bin/bash', File.join(root, 'Mode-Indicator/Restore.command'))
    abort 'Profile installed. The indicator could not be installed. You can retry Mode-Indicator/Restore.command separately.' unless ok
  end
else
  puts 'The optional SVG indicator requires a system-wide Squirrel build with mode notifications (tested on nightly d220b92).'
end
