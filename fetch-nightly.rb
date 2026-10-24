#!/usr/bin/env ruby
# Downloads the nightly packages nightly.json names into tmp/debs/<series>-<distro>-<arch>/ for build.rb --nightly,
# and verifies their build attestations. GH_TOKEN must be able to read the artifacts of sorah-rbpkg/build.
require 'fileutils'
require_relative './config.rb'

NIGHTLY_REPO = 'sorah-rbpkg/build'
NIGHTLY_WORKFLOW = 'sorah-rbpkg/build/.github/workflows/nightly.yml'

NIGHTLY.each do |series, distros|
  next if SERIES_FILTER && !SERIES_FILTER.include?(series)
  distros.each do |distro, entry|
    next if DISTRO_FILTER && !DISTRO_FILTER.include?(distro)
    entry.fetch('artifacts').each do |arch, artifact|
      next if ARCH_FILTER && !ARCH_FILTER.include?(arch)

      dir = "tmp/debs/#{series}-#{distro}-#{arch}"
      FileUtils.rm_rf(dir)
      cmd('gh', 'run', 'download', entry.fetch('run_id').to_s, '--repo', NIGHTLY_REPO, '--name', artifact, '--dir', dir)
      next unless DOIT

      debs = Dir["#{dir}/*.deb"]
      raise "#{artifact} of run #{entry.fetch('run_id')} has no packages" if debs.empty?
      debs.each do |deb|
        cmd('gh', 'attestation', 'verify', deb, '--repo', NIGHTLY_REPO, '--signer-workflow', NIGHTLY_WORKFLOW)
      end
    end
  end
end
