#!/usr/bin/env ruby
require_relative './config.rb'

PULL = !!ARGV.delete('--pull')
PUSH = !!ARGV.delete('--push')

p filters: {distro: DISTRO_FILTER, arch: ARCH_FILTER, series: SERIES_FILTER }

@built_images = []

# Pull
if PULL
  SERIES.each do |series|
    next if SERIES_FILTER && !SERIES_FILTER.include?(series.version)
    DISTROS.each do |distro|
      next if DISTRO_FILTER && !DISTRO_FILTER.include?(distro.name)

      pulled_image = [PUSH_REPOS[0]].flat_map do |repo|
        [
          "#{repo}:#{series.version}-#{distro.name}-amd64",
          "#{repo}:#{series.version}-#{distro.name}-arm64",
          "#{repo}:#{series.version}-dev-#{distro.name}-amd64",
          "#{repo}:#{series.version}-dev-#{distro.name}-arm64",
        ]
      end.find do |image|
        cmd("docker", "pull", image, exception: false)
      end
      next unless pulled_image
      cmd("docker", "tag", pulled_image, "sorah-ruby:#{series.version}-#{distro.name}")
    end
  end
end

# Build
dockerfile_template = ERB.new(File.read(File.join(__dir__, 'Dockerfile')))
dockerfile_dev_template = ERB.new(File.read(File.join(__dir__, 'Dockerfile.dev')))
Dir.mkdir('./tmp') unless File.directory?('./tmp')
SERIES.each do |series|
  next if SERIES_FILTER && !SERIES_FILTER.include?(series.version)
  DISTROS.each do |distro|
    next if DISTRO_FILTER && !DISTRO_FILTER.include?(distro.name)

    packages = apt_packages(distro.apt_url)
    pp packages if distro.name == 'trixie'

    default_version = packages.dig('ruby-defaults', 'ruby')&.map { |_| _.fetch('Version')[0] }&.grep(/#{Regexp.escape(series.version)}[.+~]/)&.sort&.last
    deb_version = packages.dig("ruby#{series.version}", "ruby#{series.version}")&.map { |_| _.fetch('Version')[0] }&.sort&.last
    unless default_version && deb_version
      puts "=> #{series.version}-#{distro.name} skipped due to inexistent package"
      next
    end

    locals = {
      ruby: series.version,
      base: {'ubuntu' => 'public.ecr.aws/ubuntu/ubuntu', 'debian' => 'public.ecr.aws/debian/debian'}.fetch(distro.family),
      distro: distro.name,
      deb_ruby: deb_version,
      deb_ruby_default: default_version,
    }

    version = deb_version.match(/^(\d+:)?([^-]+)-.+$/)[2]
    raise "version mismatch with series: series=#{series.version} deb_version=#{deb_version} version=#{version}" unless version.start_with?(series.version)

    ARCHS.each do |arch|
      next if ARCH_FILTER && !ARCH_FILTER.include?(arch)
      next if arch == 'arm64' && (!distro.arm || !series.arm)

      dockerfile = dockerfile_template.result_with_hash(locals)
      dockerfile_path = "./tmp/Dockerfile-#{series.version}-#{distro.name}-#{arch}"
      File.write(dockerfile_path, dockerfile)
      built_image = BuiltImage.new(series: series.version, version: version, distro: distro.name, dev: false, arch: arch)

      dev_dockerfile = dockerfile_dev_template.result_with_hash(locals.merge( base: "#{built_image.repo}:#{built_image.canonical_tag}" ))
      dev_dockerfile_path = "./tmp/Dockerfile.dev-#{series.version}-#{distro.name}-#{arch}"
      File.write(dev_dockerfile_path, dev_dockerfile)
      built_dev_image = BuiltImage.new(series: series.version, version: version, distro: distro.name, dev: true, arch: arch)

      cmd('docker', 'build', '--pull', '--platform', built_image.platform, '--cache-from', "#{PUSH_REPOS[0]}:#{built_image.canonical_tag}", '-t',  "#{built_image.repo}:#{built_image.canonical_tag}", '-f', dockerfile_path, __dir__)
      @built_images << built_image
      cmd('docker', 'build', '--platform', built_dev_image.platform, '--cache-from', "#{PUSH_REPOS[0]}:#{built_dev_image.canonical_tag}", '-t',  "#{built_image.repo}:#{built_dev_image.canonical_tag}", '-f', dev_dockerfile_path, __dir__)
      @built_images << built_dev_image
    end
  end
end

puts "=> Built images"
built_images_json = JSON.pretty_generate(@built_images.map(&:to_h))
File.write "tmp/built_images.json", "#{built_images_json}\n"
puts built_images_json

puts "=> Digests"
cmd('docker', 'images', 'sorah-ruby', '--digests')

if PUSH
  puts "=> Push"
  @built_images.each do |image|
    PUSH_REPOS.each do |repo|
      cmd('docker', 'tag', "#{image.repo}:#{image.canonical_tag}", "#{repo}:#{image.canonical_tag}")
      cmd('docker', 'push', "#{repo}:#{image.canonical_tag}")
    end
  end
else
  puts "=> Push (skipped)"
end
