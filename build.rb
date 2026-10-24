#!/usr/bin/env ruby
require_relative './config.rb'

PULL = !!ARGV.delete('--pull')
PUSH = !!ARGV.delete('--push')
# Builds N.M.next from the packages nightly.json names, which fetch-nightly.rb downloaded to tmp/debs/.
NIGHTLY_BUILD = !!ARGV.delete('--nightly')

p filters: {distro: DISTRO_FILTER, arch: ARCH_FILTER, series: SERIES_FILTER }, nightly: NIGHTLY_BUILD

# GitHub-hosted runners pull from Docker Hub without its rate limit, sparing public.ecr.aws for the pushes.
BASE_IMAGES = if ENV['GITHUB_ACTIONS'] == 'true'
  {'ubuntu' => 'docker.io/library/ubuntu', 'debian' => 'docker.io/library/debian'}
else
  {'ubuntu' => 'public.ecr.aws/ubuntu/ubuntu', 'debian' => 'public.ecr.aws/debian/debian'}
end

@built_images = []
@bake_targets = {}

def bake_target(image, dockerfile:, contexts: nil)
  {
    context: __dir__,
    dockerfile: File.expand_path(dockerfile, __dir__),
    platforms: [image.platform],
    tags: PUSH_REPOS.map { "#{_1}:#{image.canonical_tag}" },
    pull: PULL,
    # Read from ghcr.io, as public.ecr.aws throttles the requests of every build job starting at once.
    'cache-from': ["type=registry,ref=#{ATTEST_REPO}:#{image.canonical_tag}"],
    'cache-to': ['type=inline'],
    contexts:,
  }.compact
end

# Build
dockerfile_template = ERB.new(File.read(File.join(__dir__, 'Dockerfile')), trim_mode: '-')
dockerfile_dev_template = ERB.new(File.read(File.join(__dir__, 'Dockerfile.dev')), trim_mode: '-')
Dir.mkdir('./tmp') unless File.directory?('./tmp')
SERIES.each do |series|
  next if SERIES_FILTER && !SERIES_FILTER.include?(series.version)
  DISTROS.each do |distro|
    next if DISTRO_FILTER && !DISTRO_FILTER.include?(distro.name)

    apt_url = series.proposed ? distro.proposed_apt_url : distro.apt_url
    packages = apt_packages(apt_url)
    deb_versions = ->(pkgs) { pkgs.dig("ruby#{series.version}", "ruby#{series.version}")&.map { |_| _.fetch('Version')[0] } || [] }

    pinned = VERSIONS.dig(series.version, distro.name)
    if NIGHTLY_BUILD
      deb_version = NIGHTLY.dig(series.version, distro.name, 'version')
    elsif pinned
      # bin/publish purges the CDN before pushing a new pin, so this only waits out a stray lag.
      tries = 0
      until deb_versions.(packages).include?(pinned)
        tries += 1
        raise "#{series.version}-#{distro.name}: #{pinned} is not in #{apt_url}" if tries > 4
        $stderr.puts "#{pinned} is not in #{apt_url} yet, retrying"
        sleep 4 * 2**tries
        packages = apt_packages(apt_url, refresh: true)
      end
      deb_version = pinned
    else
      deb_version = newest_deb_version(deb_versions.(packages))
    end
    default_version = newest_deb_version(packages.dig('ruby-defaults', 'ruby')&.map { |_| _.fetch('Version')[0] }&.grep(/#{Regexp.escape(series.version)}[.+~]/) || [])
    unless default_version && deb_version
      puts "=> #{series.version}-#{distro.name} skipped due to inexistent package"
      p default_version: default_version, deb_version: deb_version
      next
    end

    locals = {
      ruby: series.version,
      base: BASE_IMAGES.fetch(distro.family),
      distro: distro.name,
      deb_ruby: deb_version,
      deb_ruby_default: default_version,
      nightly: NIGHTLY_BUILD,
      proposed: series.proposed,
    }

    upstream_version = deb_version.match(/^(\d+:)?([^-]+)-.+$/)[2]
    raise "version mismatch with series: series=#{series.version} deb_version=#{deb_version} version=#{upstream_version}" unless upstream_version.start_with?("#{series.version}.")
    version = NIGHTLY_BUILD ? "#{series.version}.next" : upstream_version

    ARCHS.each do |arch|
      next if ARCH_FILTER && !ARCH_FILTER.include?(arch)
      next if arch == 'arm64' && (!distro.arm || !series.arm)

      arch_locals = locals.merge(arch:)
      dockerfile = dockerfile_template.result_with_hash(arch_locals)
      dockerfile_path = "./tmp/Dockerfile-#{series.version}-#{distro.name}-#{arch}"
      File.write(dockerfile_path, dockerfile)
      built_image = BuiltImage.new(series: series.version, version: version, distro: distro.name, dev: false, arch: arch, nightly: NIGHTLY_BUILD)

      base_target = "#{series.version}-#{distro.name}-#{arch}".tr('.', '_')

      # The dev image builds on the base image of the same bake run, which need not be pushed or loaded first.
      dev_dockerfile = dockerfile_dev_template.result_with_hash(arch_locals.merge( base: 'base' ))
      dev_dockerfile_path = "./tmp/Dockerfile.dev-#{series.version}-#{distro.name}-#{arch}"
      File.write(dev_dockerfile_path, dev_dockerfile)
      built_dev_image = BuiltImage.new(series: series.version, version: version, distro: distro.name, dev: true, arch: arch, nightly: NIGHTLY_BUILD)
      debs = NIGHTLY_BUILD ? { debs: File.expand_path("tmp/debs/#{series.version}-#{distro.name}-#{arch}", __dir__) } : {}

      @bake_targets[base_target] = bake_target(built_image, dockerfile: dockerfile_path, contexts: debs.empty? ? nil : debs)
      @built_images << built_image
      @bake_targets["#{base_target}-dev"] = bake_target(built_dev_image, dockerfile: dev_dockerfile_path, contexts: { base: "target:#{base_target}", **debs })
      @built_images << built_dev_image
    end
  end
end

# A nightly job runs whether or not nightly.json has its series and distro yet.
raise "no images built" if @built_images.empty? && !NIGHTLY_BUILD

File.write 'tmp/bake.json', "#{JSON.pretty_generate(target: @bake_targets, group: { default: { targets: @bake_targets.keys } })}\n"
# Attestations need the image pushed by BuildKit; the local image store cannot hold them.
attest_args = PUSH ? %w(--push --provenance=mode=max --sbom=true) : %w(--load --provenance=false --sbom=false)
# Pushing to public.ecr.aws hits its rate limits when every build job pushes at once. A retry only pushes again.
cmd('docker', 'buildx', 'bake', '-f', 'tmp/bake.json', '--metadata-file', 'tmp/bake-metadata.json', *attest_args, num_retries: 8, jitter: 30_000) unless @bake_targets.empty?

puts "=> Built images"
built_images_json = JSON.pretty_generate(@built_images.map(&:to_h))
File.write "tmp/built_images.json", "#{built_images_json}\n"
puts built_images_json
