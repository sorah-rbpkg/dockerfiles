# sorah-rbpkg/dockerfiles Build Process

1. build.rb 
   - Build canonical_tag `sorah-ruby:X.Y.Z(-DEV)-{DIST}-{ARCH}` image
   - Push to repositories
   - Emit `built_images.json`
2. manifest.rb
   - Collect `built_images.json`
   - Create docker manifest for:
     - series_tag
     - series_distro_tag
     - version_tag
     - version_distro_tag
     - `latest`
