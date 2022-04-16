#!/usr/bin/env ruby
require 'json'

def cmd(*args, exception: true, num_retries: 0)
  puts "$ #{args.join(" ")}"
  tries = 0
  begin
    system(*args, exception: exception)
  rescue RuntimeError => e
    tries += 1
    wait = [(2**tries)+ (rand(2000)/1000.0), 60.0].min

    if tries > num_retries
      raise
    else
      $stderr.puts e.full_message
      $stderr.puts "Retry in #{wait}s (#{tries}/#{num_retries})"
      sleep wait
      retry
    end
  end
end

buildinfo  = JSON.parse(File.read('tmp/buildinfo.json'))
buildinfo.fetch('images').each do |tag|
  cmd('docker', 'push', tag, num_retries: 5)
end
buildinfo.fetch('manifests').each do |manifest_tag, image_tags|
  cmd('docker', 'manifest', 'create', '--amend', manifest_tag, *image_tags)
  cmd('docker', 'manifest', 'push', manifest_tag, num_retries: 5)
end
