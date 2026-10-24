require 'erb'
require 'open-uri'
require 'json'

DOIT = !(ENV['DRY_RUN'] == '1')

NUM_RETRIES = ENV['DOCKERHUB'] ? 15 : 3
RETRY_JITTER = ENV['DOCKERHUB'] ? (30*1000) : 2000
RETRY_MAX_INTERVAL = ENV['DOCKERHUB'] ? (120.0+rand(60)) : 60.0

def cmd(*args, exception: true, num_retries: NUM_RETRIES, jitter: RETRY_JITTER)
  puts "#{DOIT ? '' : '(dry-run) '}$ #{args.join(" ")}"
  tries = 0
  begin
    system(*args, exception: exception) if DOIT
  rescue RuntimeError => e
    tries += 1
    # Jitter on top of the cap keeps jobs that fail together from retrying together.
    wait = [2**tries, RETRY_MAX_INTERVAL].min + (rand(jitter)/1000.0)

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

@apt_repo_packages = {}
def apt_packages(repo_url, refresh: false)
  @apt_repo_packages.delete(repo_url) if refresh
  # source->package->versions
  @apt_repo_packages[repo_url] ||= URI.open(repo_url, 'r', &:read)
    .each_line
    .slice_after{ |_| _.chomp.empty? }
    .map { |chunk|
      chunk
        .map(&:chomp)
        .reject(&:empty?)
        .slice_before { |_| _[0] != ' ' }
        .map { |_|
          key, val = _.first.split(': ', 2)
          [key.sub(/: ?\z/,''), [val.nil? || val.empty? ? nil : val, *_[1..-1].map{ |x| x.sub(/^ /,'') }].compact]
        }.to_h
    }
    .group_by{ |_| (_['Source'] || _['Package'])[0] }
    .map{ |source, versions| [source, versions.group_by{ |_| _['Package'][0] }] }
    .to_h
end

# Debian version ordering, under which 3.3.12 is newer than 3.3.9.
def newest_deb_version(versions)
  versions.max { |a, b| a == b ? 0 : (system('dpkg', '--compare-versions', a, 'lt', b) ? -1 : 1) }
end

# Series => distro => Debian version, written by sorah-rbpkg/build's bin/publish when it releases.
VERSIONS = JSON.parse(File.read(File.join(__dir__, 'versions.json')))
# Series => distro => the nightly package built by sorah-rbpkg/build's nightly.yml, which also writes this file.
NIGHTLY = JSON.parse(File.read(File.join(__dir__, 'nightly.json')))

# A proposed series installs from <distro>-proposed of the apt repository and never takes latest.
Release = Struct.new(:version, :arm, :default_distro, :proposed, keyword_init: true)
Distro = Struct.new(:family, :name, :apt_url, :arm, keyword_init: true) do
  def proposed_apt_url = apt_url.sub("/dists/#{name}/", "/dists/#{name}-proposed/")
end
# version is N.M.next for a nightly.
BuiltImage = Struct.new(:series, :version, :distro, :dev, :arch, :nightly, keyword_init: true) do
  def repo
    'sorah-ruby'
  end

  def series_tag
    "#{series }#{dev ? '-dev' : nil}"
  end

  def series_distro_tag
    "#{series }#{dev ? '-dev' : nil}-#{distro}"
  end

  def version_tag
    "#{version}#{dev ? '-dev' : nil}"
  end

  def version_distro_tag
    "#{version}#{dev ? '-dev' : nil}-#{distro}"
  end

  def canonical_tag
    "#{version}#{dev ? '-dev' : nil}-#{distro}-#{arch}"
  end

  def platform
    "linux/#{arch}"
  end
end

DISTROS = [
  Distro.new(
    family: 'ubuntu',
    name: 'bionic',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/bionic/main/binary-amd64/Packages',
    arm: true,
  ),
  Distro.new(
    family: 'ubuntu',
    name: 'focal',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/focal/main/binary-amd64/Packages',
    arm: true,
  ),
  Distro.new(
    family: 'ubuntu',
    name: 'jammy',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/jammy/main/binary-amd64/Packages',
    arm: true,
  ),
  Distro.new(
    family: 'ubuntu',
    name: 'noble',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/noble/main/binary-amd64/Packages',
    arm: true,
  ),
  Distro.new(
    family: 'ubuntu',
    name: 'resolute',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/resolute/main/binary-amd64/Packages',
    arm: true,
  ),
  Distro.new(
    family: 'debian',
    name: 'bullseye',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/bullseye/main/binary-amd64/Packages',
    arm: true,
  ),
  Distro.new(
    family: 'debian',
    name: 'buster',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/buster/main/binary-amd64/Packages',
    arm: true,
  ),
  Distro.new(
    family: 'debian',
    name: 'bookworm',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/bookworm/main/binary-amd64/Packages',
    arm: true,
  ),
  Distro.new(
    family: 'debian',
    name: 'trixie',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/trixie/main/binary-amd64/Packages',
    arm: true,
  ),
]
# NOTE: Make sure build.jsonnet is updated as well
ARCHS = %w(arm64 amd64)
SERIES = [
  Release.new(version: '2.6', default_distro: 'focal'),
  Release.new(version: '2.7', default_distro: 'focal', arm: true),
  Release.new(version: '3.0', default_distro: 'focal', arm: true),
  Release.new(version: '3.1', default_distro: 'jammy', arm: true),
  Release.new(version: '3.2', default_distro: 'jammy', arm: true),
  Release.new(version: '3.3', default_distro: 'jammy', arm: true),
  Release.new(version: '3.4', default_distro: 'noble', arm: true),
  Release.new(version: '4.0', default_distro: 'noble', arm: true),
  Release.new(version: '4.1', default_distro: 'resolute', arm: true, proposed: true),
]

def find_series(version)
  SERIES.find { _1.version == version } or raise "series not found for #{version.inspect}"
end


PUSH_REPOS = ENV['DOCKERHUB'] ? %W(sorah/ruby) : %W(public.ecr.aws/sorah/ruby ghcr.io/sorah-rbpkg/ruby)
# GitHub artifact attestations of manifests are pushed to this registry; the others share its digests.
ATTEST_REPO = 'ghcr.io/sorah-rbpkg/ruby'

DISTRO_FILTER = ENV['DIST_FILTER']&.split(/,\s*/)
ARCH_FILTER = ENV['ARCH_FILTER']&.split(/,\s*/)
SERIES_FILTER = ENV['SERIES_FILTER']&.split(/,\s*/)
