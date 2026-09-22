# Release definitions — single source of truth shared by the Makefile
# (via `include`) and the GitHub Actions matrix (via `make print-releases`).
#
# To add a release: add its key to RELEASES, set REF_<key> / QT_<key> /
# IMAGE_<key> / CODENAME_<key>, and create docker/deps/<key>.list with its apt
# build-deps.
#
# CODENAME_<key> is the distro *codename* the build targets, and it is what the
# apt repo keys everything on: it becomes the .deb's version suffix (~trixie),
# the dist/ subdirectory, and the `release` field registered in debian-repo.
# It cannot be derived from the release key — `debian_testing` builds against
# whatever codename Debian currently calls testing (forky today) — and a rolling
# alias like `testing` is NOT a valid release there, only a real codename is.
# Ubuntu codenames work the same way, but debian-repo only accepts a codename
# listed in its own DISTS: add it there before tagging a new Ubuntu release.
#
# PKGREV_<key> is the Debian packaging revision: the -N in klassy 6.7.2-2~sid. Bump
# it to re-release the SAME klassy version after a packaging-only change (deps fix,
# maintainer change, …), and RESET it — delete the line, the default is 1 — whenever
# you bump REF_<key>, since the revision counts builds of one upstream version.
#
# This file is the source of truth for it: `make tag` puts the revision in the tag
# (debian_sid-v6.7.2-2) but CI reads the number from the tagged commit's releases.mk,
# and publish.yml fails the build if the two disagree. So commit the bump, then tag.
#
# Any value here is overridable on the CLI, e.g.
#   make build RELEASE=debian13_trixie REF_debian13_trixie=v6.7
# because command-line variables take precedence over these assignments.

RELEASES := debian13_trixie debian_testing debian_sid ubuntu2604_resolute

# Debian 13 "trixie" (stable) — Qt6 6.8 / KF6 6.13.
# v6.5.3 is the newest klassy tag trixie's libraries satisfy (it needs KF6>=6.10,
# Qt6>=6.6); v6.7+ needs KF6 6.22, which only testing/sid have.
REF_debian13_trixie      := v6.5.3
QT_debian13_trixie       := 6
IMAGE_debian13_trixie    := debian:trixie-slim
CODENAME_debian13_trixie := trixie

# Debian testing (rolling; currently "forky") — Qt6 6.10 / KF6 6.28.
# CODENAME must track whatever Debian calls testing: when forky is promoted to
# stable, update this to the next testing codename (and debian-repo's DISTS).
REF_debian_testing      := v6.7.2
QT_debian_testing       := 6
IMAGE_debian_testing    := debian:testing-slim
CODENAME_debian_testing := forky

# Debian unstable "sid" — Qt6 6.10 / KF6 6.30
REF_debian_sid      := v6.7.2
QT_debian_sid       := 6
IMAGE_debian_sid    := debian:sid-slim
CODENAME_debian_sid := sid

# Ubuntu 26.04 LTS "resolute" — Qt6 6.10.2 / KF6 6.24 / KDecoration3 6.6.
# Satisfies v6.7.2's floors (Qt6 >= 6.10, KF6 >= 6.22), so it tracks the latest
# klassy tag like sid does. Not a Debian suite, but the build is distro-agnostic:
# the package names in docker/deps/ are identical to sid's, since Ubuntu inherits
# Debian's KF6/Qt6 packaging. Keep this pinned to the LTS, not a rolling Ubuntu:
# an interim release EOLs in 9 months and would silently rot the apt repo entry.
REF_ubuntu2604_resolute      := v6.7.2
QT_ubuntu2604_resolute       := 6
IMAGE_ubuntu2604_resolute    := ubuntu:26.04
CODENAME_ubuntu2604_resolute := resolute
