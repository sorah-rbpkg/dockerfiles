# sorah-rbpkg Docker images

![docker-build](https://github.com/sorah-rbpkg/dockerfiles/workflows/docker-build/badge.svg)

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

- SERIES is like `2.6`, `2.7`, `3.0`, `3.1`
- DISTRO is like `bionic`, `focal`, `jammy`, `buster`, `bullseye`

### List

- 2.6: `2.6`, `2.6-dev` (dist= __`focal`__, `bionic`, `buster`)
- 2.7: `2.7`, `2.7-dev` (dist= __`focal`__, `bionic`, `bullseye`, `buster`)
- 3.0: `3.0`, `3.0-dev` (dist= `jammy`, __`focal`__, `bionic`, `bullseye`, `buster`)
- 3.1: `3.1`, `3.1-dev` (dist= __`jammy`__, `focal`, `bionic`, `bullseye`)

_distro in bold is default_

## aarch64 (arm64 support)

images are built on amd64 (x86_64) and arm64 (aarch64) since 2.7.
