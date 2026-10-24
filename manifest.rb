#!/usr/bin/env ruby
require_relative './config.rb'

DO_SUBTAG = !!ARGV.delete('--subtag')
DO_LATEST = !!ARGV.delete('--latest')

Manifest = Struct.new(:kind, :name, :images, keyword_init: true)

p filters: {distro: DISTRO_FILTER, series: SERIES_FILTER }

@built_images = JSON.parse(File.read("tmp/built_images.json"))
  .map { BuiltImage.new(_1) }
  .select {
    next false if SERIES_FILTER && !SERIES_FILTER.include?(_1.series)
    next false if DISTRO_FILTER && !DISTRO_FILTER.include?(_1.distro)
    true
  }

@manifests = {}

# A nightly is tagged N.M.next only, never as its series or latest.
@released_images = @built_images.reject(&:nightly)

# series_tag
@manifests.merge!(
  @released_images.group_by(&:series_tag).map do |tag, images|
    series = find_series(images[0].series)
    next unless series.default_distro
    latest_version = images.map(&:version).sort.last
    [tag, Manifest.new(kind: :subtag, name: tag, images: images.select { _1.version == latest_version && _1.distro == series.default_distro })]
  end.compact.to_h,
)

# series_distro_tag
@manifests.merge!(
  @released_images.group_by(&:series_distro_tag).map do |tag, images|
    latest_version = images.map(&:version).sort.last
    [tag, Manifest.new(kind: :subtag, name: tag, images: images.select { _1.version == latest_version })]
  end.compact.to_h,
)

# version_tag
@manifests.merge!(
  @built_images.group_by(&:version_tag).map do |tag, images|
    series = find_series(images[0].series)
    next unless series.default_distro
    [tag, Manifest.new(kind: :subtag, name: tag, images: images.select { _1.distro == series.default_distro })]
  end.compact.to_h,
)

# version_distro_tag
@manifests.merge!(
  @built_images.group_by(&:version_distro_tag).map do |tag, images|
    [tag, Manifest.new(kind: :subtag, name: tag, images: images)]
  end.compact.to_h,
)

# latest_tag
latest_series = SERIES.last
@manifests["#{latest_series.version}-#{latest_series.default_distro}"]&.then do |manifest|
  @manifests['latest'] = manifest.clone.tap { _1.kind = :latest; _1.name = 'latest' }
end
@manifests["#{latest_series.version}-dev-#{latest_series.default_distro}"]&.then do |manifest|
  @manifests['latest-dev'] = manifest.clone.tap { _1.kind = :latest; _1.name = 'latest-dev' }
end

@manifests.reject! { _2.images.empty? }

@digests = []

# imagetools create keeps the attestation manifests BuildKit pushed along each per-arch image.
def create_manifest(manifests)
  manifests.each_value { |manifest|
    images = manifest.images.map(&:canonical_tag)
    p manifest.name => manifest.images.map(&:canonical_tag)
    raise "manifest with more than 2 images: #{manifest.inspect}" if images.size > 2
  }
  manifests.values.group_by { _1.images.map(&:canonical_tag).sort }.each do |canonical_tags, group|
    dev = group[0].images[0].dev
    PUSH_REPOS.each do |repo|
      metadata_path = "tmp/imagetools-#{repo.tr('/:', '__')}-#{canonical_tags[0]}.json"
      cmd('docker', 'buildx', 'imagetools', 'create', '--metadata-file', metadata_path, *group.flat_map { ['-t', "#{repo}:#{_1.name}"] }, *canonical_tags.map { "#{repo}:#{_1}" })
      next unless DOIT
      @digests << { repo:, dev:, tags: group.map(&:name), digest: JSON.parse(File.read(metadata_path)).fetch('containerimage.descriptor').fetch('digest') }
    end
  end
end

create_manifest(@manifests.select { _2.kind == :subtag }) if DO_SUBTAG
create_manifest(@manifests.select { _2.kind == :latest }) if DO_LATEST

File.write 'tmp/manifest_digests.json', "#{JSON.pretty_generate(@digests)}\n"
puts JSON.pretty_generate(@digests)

# Read by the attest steps of the workflow, one per digest.
if ENV['GITHUB_OUTPUT'] && PUSH_REPOS.include?(ATTEST_REPO)
  outputs = @digests.select { _1[:repo] == ATTEST_REPO }.group_by { _1[:dev] ? 'dev' : 'base' }.map do |kind, digests|
    raise "#{ATTEST_REPO} got several #{kind} digests: #{digests.inspect}" if digests.map { _1[:digest] }.uniq.size > 1
    "#{kind}=#{digests[0][:digest]}\n"
  end
  File.write(ENV['GITHUB_OUTPUT'], "name=#{ATTEST_REPO}\n#{outputs.join}", mode: 'a')
end
