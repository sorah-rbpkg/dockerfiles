# sorah-rbpkg Docker images

![docker-build](https://github.com/sorah-rbpkg/dockerfiles/workflows/docker-build/badge.svg)

## Public repository

- https://gallery.ecr.aws/d6b1h6s1/ruby
- https://hub.docker.com/r/sorah/ruby

## Image tag

- base
  - `public.ecr.aws/d6b1h6s1/ruby:{SERIES}`
  - `public.ecr.aws/d6b1h6s1/ruby:{SERIES}-{DISTRO}`
- with build-essential
  - `public.ecr.aws/d6b1h6s1/ruby:{SERIES}-dev`
  - `public.ecr.aws/d6b1h6s1/ruby:{SERIES}-dev-{DISTRO}`

where,

- SERIES is like `2.5`, `2.6`, `2.7`
- DISTRO is like `bionic`, `focal`, `buster`

### List

- 2.5.8: `2.5`, `2.5-dev` (dist=`bionic`)
- 2.6.6: `2.6`, `2.6-dev` (dist=`focal`, `bionic`, `buster`)
- 2.7.1: `2.7`, `2.7-dev` (dist=`focal`, `bionic`, `buster`)

## aarch64 (arm64 support)

2.7 images are built on amd64 (x86_64) and arm64 (aarch64).
