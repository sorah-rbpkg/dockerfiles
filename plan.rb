#!/usr/bin/env ruby
# Decides what docker-build builds, as the outputs all and targets ("SERIES-DISTRO" names).
# A push that changes only versions.json builds what it changed; anything else, the schedule included, builds all.
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

before = ENV['BEFORE'].to_s
output(all: true) if ENV.fetch('GITHUB_EVENT_NAME') != 'push' || before.empty? || before.match?(/\A0+\z/)

changed = git('diff', '--name-only', before, 'HEAD')&.lines(chomp: true)
output(all: true) unless changed == ['versions.json']

old = git('show', "#{before}:versions.json")&.then { |json| JSON.parse(json) }
output(all: true) unless old

new = JSON.parse(File.read(File.join(__dir__, 'versions.json')))
output(all: false, targets: new.flat_map { |series, distros| distros.filter_map { |distro, version| "#{series}-#{distro}" if old.dig(series, distro) != version } })
