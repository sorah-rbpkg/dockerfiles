# sorah-rbpkg Docker images

![docker-build](https://github.com/sorah-rbpkg/dockerfiles/workflows/docker-build/badge.svg)

<a href='https://ko-fi.com/J3J8CKMUU' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://cdn.ko-fi.com/cdn/kofi3.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

## Public repositories

- [ghcr.io/sorah-rbpkg/ruby](https://github.com/sorah-rbpkg/dockerfiles/pkgs/container/ruby)
- [public.ecr.aws/sorah/ruby](https://gallery.ecr.aws/sorah/ruby)
- [sorah/ruby](https://hub.docker.com/r/sorah/ruby) _(deprecated, no longer guaranteed to be updated)_

## Image tag

- base
  - `{SERIES}`
  - `{SERIES}-{DISTRO}`
- with build-essential
  - `{SERIES}-dev`
  - `{SERIES}-dev-{DISTRO}`

where,

- SERIES is like `2.6`, `2.7`, `3.0`, `3.1`, `3.2`, `3.3`, `3.4`, `4.0`, `4.1`
  - Starting Ruby 3.2.0, 3.1.3, 3.0.5, 2.7.7 and later versions, you can specify full version number as SERIES as well
- DISTRO is like `focal`, `jammy`, `noble`, `bookworm`, `trixie`

for instance: `public.ecr.aws/sorah/ruby:3.2-dev-noble`, `public.ecr.aws/sorah/ruby:3.4-trixie`, `public.ecr.aws/sorah/ruby:3.3`

### List

- `2.6`, `2.6-dev` distro= `bionic`, __`focal`__, `buster`
- `2.7`, `2.7-dev` distro= `bionic`, __`focal`__, `bullseye`, `buster`
- `3.0`, `3.0-dev` distro= `bionic`, __`focal`__, `jammy`, `bullseye`, `buster`
- `3.1`, `3.1-dev` distro= `bionic`, `focal`, __`jammy`__, `bullseye`
- `3.2`, `3.2-dev` distro= `focal`, __`jammy`__, `noble`, `bullseye`, `bookworm`
- `3.3`, `3.3-dev` distro= `focal`, __`jammy`__, `noble`, `bullseye`, `bookworm`, `trixie`
- `3.4`, `3.4-dev` distro= `jammy`, __`noble`__, `resolute`, `bookworm`, `trixie`
- `4.0`, `4.0-dev` distro= `jammy`, __`noble`__, `resolute`, `bookworm`, `trixie`
- `4.1`, `4.1-dev` distro= `noble`, __`resolute`__, `trixie` (preview, from the `-proposed` suites; never `latest`)

_a distro marked bold is default - used on tags which omits DISTRO_

### Nightly

`{SERIES}.next`, `{SERIES}.next-{DISTRO}`, `{SERIES}.next-dev` and `{SERIES}.next-dev-{DISTRO}` install a weekly package of the tip of Ruby's `ruby_N_M` branch, for `3.3`, `3.4` and `4.0` on the distros of their list above. They are for trying fixes before their release, and are rebuilt with each new snapshot without any review.

The package is `rubyN.M` of version `<X.Y.Z>+git<YYYYMMDD>.g<commit>-0nkmi0~<distro>`, built by [sorah-rbpkg/build](https://github.com/sorah-rbpkg/build)'s `nightly.yml` and not in the apt repository. Its `ruby-defaults` and `rubygems-integration` are the released ones.

## Misc

### aarch64 (arm64 support)

images are built on amd64 (x86_64) and arm64 (aarch64) since 2.7.

### Pin

The image has the following pinning with apt_preferences(5):

- `src:rubygems-integration`, `src:ruby2.*`, `src:ruby3.*` (specified individually) has pin-priority of 600.
- `src:ruby-defaults` has pin-priority of 999 with the latest version installed on build.

### CI

The images is built using GitHub Actions. Some older distros/series have been stopped building: `bionic` and earlier, `bullseye` and earlier, and Ruby 2.7 and earlier.

### Attestations

Images on ghcr.io and public.ecr.aws carry BuildKit's SLSA provenance (`mode=max`) and SBOM attestations for each platform:

```
docker buildx imagetools inspect ghcr.io/sorah-rbpkg/ruby:3.4 --format '{{json .Provenance}}'
docker buildx imagetools inspect ghcr.io/sorah-rbpkg/ruby:3.4 --format '{{json .SBOM}}'
```

Each multi-platform image also has a GitHub artifact attestation, which verifies on either registry as they share digests:

```
gh attestation verify oci://public.ecr.aws/sorah/ruby:3.4 --repo sorah-rbpkg/dockerfiles
```

### Versions

[`versions.json`](./versions.json) pins the Debian version of `rubyX.Y` each series and distro installs, and a build fails when the apt repository does not have it. [sorah-rbpkg/build](https://github.com/sorah-rbpkg/build)'s `bin/publish` updates and pushes it after releasing packages. A push that changes only `versions.json` builds just the series and distros it changed; other pushes and the scheduled rebuild build everything. Series and distros without a pin install the newest version in the apt repository.

[`nightly.json`](./nightly.json) is the same for the nightly images, naming the run of sorah-rbpkg/build and its artifacts that hold each package. That run's `nightly.yml` pushes it once the packages pass their smoke test, and a push that changes only it builds just the nightly images it changed. The build verifies the packages' attestations from `nightly.yml` before installing them.
