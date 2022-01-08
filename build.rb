require 'erb'
require 'open-uri'
require 'json'

def cmd(*args, exception: true)
  puts "$ #{args.join(" ")}"
  system(*args, exception: exception)
end

@apt_repo_packages = {}
def apt_packages(repo_url)
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

Release = Struct.new(:version, :arm, keyword_init: true)
Distro = Struct.new(:family, :name, :apt_url, :arm, keyword_init: true)
BuiltImage = Struct.new(:series, :distro, :dev, :arch, keyword_init: true) do
  def repo
    'sorah-ruby'
  end

  def series_tag
    "#{series}#{dev ? '-dev' : nil}"
  end

  def manifest_tag
    "#{series_tag}-#{distro}"
  end

  def arch_tag
    "#{manifest_tag}-#{arch}"
  end

  def platform
    "linux/#{arch}"
  end
end

DISTROS = [
  Distro.new(
    family: 'ubuntu',
    name: 'focal',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/focal/main/binary-amd64/Packages',
    arm: true,
  ),
  Distro.new(
    family: 'debian',
    name: 'bullseye',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/bullseye/main/binary-amd64/Packages',
    arm: true,
  ),
  Distro.new(
    family: 'ubuntu',
    name: 'bionic',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/bionic/main/binary-amd64/Packages',
    arm: true,
  ),
  Distro.new(
    family: 'debian',
    name: 'buster',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/buster/main/binary-amd64/Packages',
    arm: true,
  ),
]
SERIES = [
  Release.new(version: '2.6'),
  Release.new(version: '2.7', arm: true),
  Release.new(version: '3.0', arm: true),
  Release.new(version: '3.1', arm: true),
]
PUSH_REPOS = %W(sorah/ruby gcr.io/#{ENV['GCP_PROJECT']}/ruby public.ecr.aws/sorah/ruby)
PULL = !!ARGV.delete('--pull')
PUSH = !!ARGV.delete('--push')

@built_images = []

# Pull
if PULL
  SERIES.each do |series|
    DISTROS.each do |distro|
      pulled_image = PUSH_REPOS.flat_map do |repo|
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
  DISTROS.each do |distro|
    packages = apt_packages(distro.apt_url)

    default_version = packages.dig('ruby-defaults', 'ruby')&.map { |_| _.fetch('Version')[0] }&.grep(/#{Regexp.escape(series.version)}\./)&.sort&.last
    version = packages.dig("ruby#{series.version}", "ruby#{series.version}")&.map { |_| _.fetch('Version')[0] }&.sort&.last
    next unless default_version && version

    locals = {
      ruby: series.version,
      base: distro.family,
      distro: distro.name,
      deb_ruby: version,
      deb_ruby_default: default_version,
    }

    %w(arm64 amd64).each do |arch|
      next if arch == 'arm64' && (!distro.arm || !series.arm)
      dockerfile = dockerfile_template.result_with_hash(locals)
      dockerfile_path = "./tmp/Dockerfile-#{series.version}-#{distro.name}-#{arch}"
      File.write(dockerfile_path, dockerfile)
      built_image = BuiltImage.new(series: series.version, distro: distro.name, dev: false, arch: arch)

      dev_dockerfile = dockerfile_dev_template.result_with_hash(locals.merge( base: "#{built_image.repo}:#{built_image.arch_tag}" ))
      dev_dockerfile_path = "./tmp/Dockerfile.dev-#{series.version}-#{distro.name}-#{arch}"
      File.write(dev_dockerfile_path, dev_dockerfile)
      built_dev_image = BuiltImage.new(series: series.version, distro: distro.name, dev: true, arch: arch)

      cmd('docker', 'build', '--pull', '--platform', built_image.platform, '--cache-from', "#{built_image.repo}:#{built_image.arch_tag}", '-t',  "#{built_image.repo}:#{built_image.arch_tag}", '-f', dockerfile_path, __dir__)
      @built_images << built_image
      cmd('docker', 'build', '--platform', built_dev_image.platform, '--cache-from', "#{built_image.repo}:#{built_dev_image.arch_tag}", '-t',  "#{built_image.repo}:#{built_dev_image.arch_tag}", '-f', dev_dockerfile_path, __dir__)
      @built_images << built_dev_image
    end
  end
end

manifests = @built_images.group_by(&:manifest_tag)
@built_images.group_by(&:series_tag).transform_values { |is| is[0].manifest_tag }.each do |(series, manifest_tag)|
  manifests[series] = manifests.fetch(manifest_tag)
end
manifests['latest'] = manifests.fetch(manifests.fetch(SERIES.last.version).first.manifest_tag)
manifests['latest-dev'] = manifests.fetch(manifests.fetch("#{SERIES.last.version}-dev").first.manifest_tag)
pp manifests


if PUSH
  buildinfo = {"images" => [], "manifests" => {}}
  @built_images.each do |image|
    PUSH_REPOS.each do |repo|
      cmd('docker', 'tag', "#{image.repo}:#{image.arch_tag}", "#{repo}:#{image.arch_tag}")
      buildinfo['images'] << "#{repo}:#{image.arch_tag}"
    end
  end

  manifests.each do |manifest_tag, images|
    PUSH_REPOS.each do |repo|
      buildinfo['manifests']["#{repo}:#{manifest_tag}"] = images.map { |_| "#{repo}:#{_.arch_tag}" }
    end
  end
  p buildinfo
  File.write "tmp/buildinfo.json", "#{buildinfo.to_json}\n"
end

pp manifests
cmd('docker', 'images', 'sorah-ruby', '--digests')
