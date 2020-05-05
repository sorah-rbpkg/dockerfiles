# sorah-rbpkg Docker images

![docker-build](https://github.com/sorah-rbpkg/dockerfiles/workflows/docker-build/badge.svg)

## Public repository

https://hub.docker.com/r/sorah/ruby

## Image tag

- base
  - `sorah/ruby:{SERIES}`
  - `sorah/ruby:{SERIES}-{DISTRO}`
- with build-essential
  - `sorah/ruby:{SERIES}-dev`
  - `sorah/ruby:{SERIES}-{DISTRO}-dev`

where,

- SERIES is like `2.5`, `2.6`, `2.7`
- DISTRO is like `bionic`, `focal`, `buster`

### List

- 2.5.8: `2.5`, `2.5-dev` (dist=`bionic`)
- 2.6.6: `2.6`, `2.6-dev` (dist=`focal`, `bionic`, `buster`)
- 2.7.1: `2.7`, `2.7-dev` (dist=`focal`, `bionic`, `buster`)
