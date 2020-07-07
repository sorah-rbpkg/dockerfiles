#!/usr/bin/env ruby
require 'json'

def cmd(*args, exception: true)
  puts "$ #{args.join(" ")}"
  system(*args, exception: exception)
end

buildinfo  = JSON.parse(File.read('tmp/buildinfo.json'))
buildinfo.fetch('images').each do |tag|
  cmd('docker', 'push', tag)
end
buildinfo.fetch('manifests').each do |manifest_tag, image_tags|
  cmd('docker', 'manifest', 'create', '--amend', manifest_tag, image_tagss)
  cmd('docker', 'manifest', 'push', manifest_tag)
end
