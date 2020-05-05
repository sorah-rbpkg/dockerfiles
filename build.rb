require 'erb'
require 'open-uri'

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

Distro = Struct.new(:family, :name, :apt_url, keyword_init: true)
DISTROS = [
  Distro.new(
    family: 'ubuntu',
    name: 'focal',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/focal/main/binary-amd64/Packages',
  ),
  Distro.new(
    family: 'debian',
    name: 'buster',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/buster/main/binary-amd64/Packages',
  ),
  Distro.new(
    family: 'ubuntu',
    name: 'bionic',
    apt_url: 'https://cache.ruby-lang.org/lab/sorah/deb/dists/bionic/main/binary-amd64/Packages',
  ),
]
SERIES = %w(2.5 2.6 2.7)
REPO = 'sorah-ruby'
PUSH_REPOS = %W(sorah/ruby gcr.io/#{ENV['GCP_PROJECT']}/ruby)
PULL = true
PUSH = !!ARGV.delete('--push')

@built_tags_by_series = {}

# Pull
if PULL
  SERIES.each do |series|
    DISTROS.each do |distro|
      pulled_image = PUSH_REPOS.find do |repo|
        image =  "#{repo}:#{series}-#{distro.name}"
        cmd("docker", "pull", image, exception: false) or next
        image
      end
      next unless pulled_image
      cmd("docker", "tag", pulled_image, "#{REPO}:#{series}-#{distro.name}")
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

    default_version = packages.dig('ruby-defaults', 'ruby')&.map { |_| _.fetch('Version')[0] }&.grep(/#{Regexp.escape(series)}\./)&.sort&.last
    version = packages.dig("ruby#{series}", "ruby#{series}")&.map { |_| _.fetch('Version')[0] }&.sort&.last
    next unless default_version && version

    locals = {
      ruby: series,
      base: distro.family,
      distro: distro.name,
      deb_ruby: version,
      deb_ruby_default: default_version,
    }

    dockerfile = dockerfile_template.result_with_hash(locals)
    dockerfile_path = "./tmp/Dockerfile-#{series}-#{distro.name}"
    File.write(dockerfile_path, dockerfile)
    tag = "#{REPO}:#{series}-#{distro.name}"
    cmd('docker', 'build', '--pull', '--cache-from', tag, '-t', tag, '-f', dockerfile_path, __dir__)
    (@built_tags_by_series[series] ||= []) << tag

    dev_dockerfile = dockerfile_dev_template.result_with_hash(locals.merge(
      base: REPO,
    ))
    dev_dockerfile_path = "./tmp/Dockerfile.dev-#{series}-#{distro.name}"
    File.write(dev_dockerfile_path, dev_dockerfile)
    dev_tag = "#{REPO}:#{series}-dev-#{distro.name}"
    cmd('docker', 'build', '--cache-from', dev_tag, '-t', dev_tag, '-f', dev_dockerfile_path, __dir__)
    (@built_tags_by_series["#{series}-dev"] ||= []) << tag
  end
end

@built_tags_by_series['latest'] = [
  @built_tags_by_series.fetch(SERIES.last).first,
]
@built_tags_by_series['latest-dev'] = [
  @built_tags_by_series.fetch("#{SERIES.last}-dev").first,
]

pp @built_tags_by_series

@built_tags_by_series.each do |series, tags|
  tag =  "#{REPO}:#{series}"
  cmd('docker', 'tag', tags.first, tag)
  tags << tag
end

cmd('docker', 'images', 'sorah-ruby', '--digests')

if PUSH
  @built_tags_by_series.each do |series, tags|
    tags.each do |tag|
      tag_only = tag.split(?:, 2)[1]
      PUSH_REPOS.each do |repo|
        push_tag =  "#{repo}:#{tag_only}"
        cmd('docker', 'tag', tag, push_tag)
        cmd('docker', 'push', push_tag)
      end
    end
  end
end
