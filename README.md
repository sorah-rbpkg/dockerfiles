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
- DISTRO is like `bionic`, `focal`, `buster`, `bullseye`

### List

- 2.6: `2.6`, `2.6-dev` (dist=`focal`, `bionic`, `buster`)
- 2.7: `2.7`, `2.7-dev` (dist=`focal`, `bionic`, `bullseye`, `buster`)
- 3.0: `3.0`, `3.0-dev` (dist=`focal`, `bionic`, `bullseye`, `buster`)
- 3.1: `3.1`, `3.1-dev` (dist=`focal`, `bionic`, `bullseye`)

## aarch64 (arm64 support)

images are built on amd64 (x86_64) and arm64 (aarch64) except 2.6.
