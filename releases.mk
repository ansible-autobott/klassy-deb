# Release definitions — single source of truth shared by the Makefile
# (via `include`) and the GitHub Actions matrix (via `make print-releases`).
#
# To add a release: add its key to RELEASES, set REF_<key> / QT_<key> /
# IMAGE_<key>, and create docker/deps/<key>.list with its apt build-deps.
#
# Any value here is overridable on the CLI, e.g.
#   make build RELEASE=debian13_trixie REF_debian13_trixie=v6.7
# because command-line variables take precedence over these assignments.

RELEASES := debian13_trixie debian_testing debian_sid

# Debian 13 "trixie" (stable) — Qt6 6.8 / KF6 6.13.
# v6.5.3 is the newest klassy tag trixie's libraries satisfy (it needs KF6>=6.10,
# Qt6>=6.6); v6.7+ needs KF6 6.22, which only testing/sid have.
REF_debian13_trixie   := v6.5.3
QT_debian13_trixie    := 6
IMAGE_debian13_trixie := debian:trixie-slim

# Debian testing (rolling; currently "forky") — Qt6 6.10 / KF6 6.28
REF_debian_testing   := v6.7.2
QT_debian_testing    := 6
IMAGE_debian_testing := debian:testing-slim

# Debian unstable "sid" — Qt6 6.10 / KF6 6.30
REF_debian_sid   := v6.7.2
QT_debian_sid    := 6
IMAGE_debian_sid := debian:sid-slim
