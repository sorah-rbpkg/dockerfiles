# sorah-rbpkg Docker images

![docker-build](https://github.com/sorah-rbpkg/dockerfiles/workflows/docker-build/badge.svg)

<a href='https://ko-fi.com/J3J8CKMUU' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://cdn.ko-fi.com/cdn/kofi3.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

## Public repository

- https://gallery.ecr.aws/sorah/ruby
- https://hub.docker.com/r/sorah/ruby

## Image tag

- base
  - `public.ecr.aws/sorah/ruby:{SERIES}`
  - `public.ecr.aws/sorah/ruby:{SERIES}-{DISTRO}`
- with build-essential
  - `public.ecr.aws/sorah/ruby:{SERIES}-dev`
  - `public.ecr.aws/sorah/ruby:{SERIES}-dev-{DISTRO}`

where,

- SERIES is like `2.6`, `2.7`, `3.0`, `3.1`, `3.2`
  - Starting Ruby 3.2.0, 3.1.3, 3.0.5, 2.7.7, you can specify full version number as SERIES as well
- DISTRO is like `bionic`, `focal`, `jammy`, `buster`, `bullseye`, `bookworm`

### List

- 2.6: `2.6`, `2.6-dev` (dist= __`focal`__, `bionic`, `buster`)
- 2.7: `2.7`, `2.7-dev` (dist= __`focal`__, `bionic`, `bullseye`, `buster`)
- 3.0: `3.0`, `3.0-dev` (dist= `jammy`, __`focal`__, `bionic`, `bullseye`, `buster`)
- 3.1: `3.1`, `3.1-dev` (dist= __`jammy`__, `focal`, `bionic`, `bullseye`)
- 3.2: `3.2`, `3.2-dev` (dist= __`jammy`__, `focal`, `bionic`, `bookworm`)
- 3.3: `3.3`, `3.3-dev` (dist= __`jammy`__, `focal`, `bionic`, `bookworm`)

_distro in bold is default_

## Misc

### aarch64 (arm64 support)

images are built on amd64 (x86_64) and arm64 (aarch64) since 2.7.

### Pin

The image has the following pinning with apt_preferences(5):

- `src:rubygems-integration`, `src:ruby2.*`, `src:ruby3.*` (specified individually) has pin-priority of 600.
- `src:ruby-defaults` has pin-priority of 999 with the latest version installed on build.
