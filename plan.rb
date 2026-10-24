#!/usr/bin/env ruby
# Decides what docker-build builds, as the outputs all and targets ("SERIES-DISTRO" names, "nightly-SERIES-DISTRO" for
# N.M.next). A push that changes only versions.json or nightly.json builds what it changed; anything else, the schedule
# included, builds all.
require 'json'
require 'open3'

def output(all:, targets: [])
  puts "all=#{all} targets=#{targets.join(' ')}"
  File.open(ENV.fetch('GITHUB_OUTPUT'), 'a') { |io| io.puts "all=#{all}", "targets=#{JSON.generate(targets)}" }
  exit
end

def git(*args)
  out, status = Open3.capture2('git', *args)
  status.success? ? out : nil
end

# SERIES-DISTRO of each entry of file that differs from the commit before.
def changed_entries(before, file)
  old = git('show', "#{before}:#{file}")&.then { |json| JSON.parse(json) }
  output(all: true) unless old

  new = JSON.parse(File.read(File.join(__dir__, file)))
  new.flat_map { |series, distros| distros.filter_map { |distro, entry| "#{series}-#{distro}" if old.dig(series, distro) != entry } }
end

before = ENV['BEFORE'].to_s
output(all: true) if ENV.fetch('GITHUB_EVENT_NAME') != 'push' || before.empty? || before.match?(/\A0+\z/)

changed = git('diff', '--name-only', before, 'HEAD')&.lines(chomp: true)
output(all: true) if changed.nil? || changed.empty? || !(changed - %w(versions.json nightly.json)).empty?

targets = []
targets.concat(changed_entries(before, 'versions.json')) if changed.include?('versions.json')
targets.concat(changed_entries(before, 'nightly.json').map { "nightly-#{_1}" }) if changed.include?('nightly.json')
output(all: false, targets:)
