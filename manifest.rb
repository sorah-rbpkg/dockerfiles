#!/usr/bin/env ruby
require_relative './config.rb'

PULL = !!ARGV.delete('--pull')
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

# series_tag
@manifests.merge!(
  @built_images.group_by(&:series_tag).map do |tag, images|
    series = find_series(images[0].series)
    next unless series.default_distro
    latest_version = images.map(&:version).sort.last
    [tag, Manifest.new(kind: :subtag, name: tag, images: images.select { _1.version == latest_version && _1.distro == series.default_distro })]
  end.compact.to_h,
)

# series_distro_tag
@manifests.merge!(
  @built_images.group_by(&:series_distro_tag).map do |tag, images|
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

def create_manifest(manifests)
  @manifests.each_value { |manifest|
    images = manifest.images.map(&:canonical_tag)
    p manifest.name => manifest.images.map(&:canonical_tag)
    raise "manifest with more than 2 images: #{manifest.inspect}" if images.size > 2
  }
  @manifests.each do |manifest_name, manifest|
    PUSH_REPOS.each do |repo|
      if PULL
        manifest.images do |image|
          cmd('docker', 'pull', "#{repo}:#{image.canonical_tag}")
        end
      end
      name = "#{repo}:#{manifest.name}"
      cmd('docker', 'manifest', 'create', '--amend', name, *(manifest.images.map { "#{repo}:#{_1.canonical_tag}" }))
      cmd('docker', 'manifest', 'push', name)
    end
  end
end

create_manifest(@manifests.select { _2.kind == :subtag }) if DO_SUBTAG
create_manifest(@manifests.select { _2.kind == :latest }) if DO_LATEST
