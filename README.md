# klassy-deb

Build the [Klassy](https://github.com/paulmcauley/klassy) KDE Plasma theme
(window decoration + application style) as installable **`.deb`** packages for
several Debian releases. Each release is compiled inside its own Docker
container so it links against that release's Qt / KDE Frameworks stack.

## Why per-release Docker builds

Klassy pins minimum Qt6 / KDE Frameworks 6 versions, and Debian's stable,
testing, and unstable suites ship different Qt6/KF6 versions. So each release
builds in its own container against that suite's libraries, pinning a klassy
tag those libraries can satisfy:

| Release           | Base image            | klassy ref (default) |
|-------------------|-----------------------|----------------------|
| `debian13_trixie` | `debian:trixie-slim`  | `v6.5.3`             |
| `debian_testing`  | `debian:testing-slim` | `v6.7.2`             |
| `debian_sid`      | `debian:sid-slim`     | `v6.7.2`             |

All three build the Qt6 / KF6 / KDecoration3 stack.

Each release sets its base image via `IMAGE_<release>` in `releases.mk` — the
release keys are just labels and don't have to match a Docker tag.

Each ref is pinned to its suite's libraries: trixie (KF6 6.13, Qt6 6.8) builds
klassy `v6.5.3`, while testing/sid (KF6 6.28/6.30, Qt6 6.10) build the latest
`v6.7.2` — `v6.7+` requires KF6 6.22. To retarget a release, override its ref:

```sh
make build RELEASE=debian13_trixie REF_debian13_trixie=v6.7   # + tune its deps list
```

## Quick start

```sh
make                                  # help
make build RELEASE=debian13_trixie    # clone -> image -> compile -> package
make build-all                        # build every release in $(RELEASES)
make list                             # show built .deb files
```

The klassy source is cloned into `src/klassy/` and packages land in
`dist/<release>/` — both are git-ignored.

## Layout

```
.
├── Makefile                     # clone / build / package targets
├── releases.mk                  # single source of truth: releases + refs + base images
├── docker/
│   ├── Dockerfile               # ARG BASE_IMAGE + RELEASE -> per-release build
│   ├── build-package.sh         # cmake build + install -> dpkg-deb
│   └── deps/<release>.list      # apt build-deps per release (tunable)
├── src/klassy/                  # (git-ignored) upstream clone
├── dist/<release>/*.deb         # (git-ignored) built artifacts
└── .github/workflows/build.yml  # matrix CI derived from `make print-releases`
```

## Targets

Run `make help` for the full list. Highlights:

| Target       | Purpose                                                    |
|--------------|------------------------------------------------------------|
| `clone`      | clone klassy into `src/klassy` (idempotent)                |
| `update`     | fetch + checkout the pinned ref for `RELEASE`              |
| `image`      | build the builder image for `RELEASE`                      |
| `build`      | compile in Docker and emit a `.deb` into `dist/RELEASE/`   |
| `build-all`  | run `build` for every release in `$(RELEASES)`             |
| `shell`      | drop into the builder image for debugging                  |
| `list`       | list built `.deb` files                                    |
| `clean` / `clean-all` | remove `dist/` (and the clone)                    |
| `ci-build`   | thin entrypoint used by GitHub Actions                     |
| `print-releases` | print `$(RELEASES)` as JSON (feeds the CI matrix)      |

## Adding / tuning a release

Everything lives in `releases.mk` (`RELEASES` + `REF_<key>` / `QT_<key>` /
`IMAGE_<key>`) plus a matching `docker/deps/<key>.list`. Add a line to each and
the Makefile *and* CI pick it up automatically.

Each release's build deps in `docker/deps/<release>.list` (one apt package per
line; `#` comments allowed) are a best-effort starting point taken from klassy's
`find_package()` list and `.kde-ci.yml`. If `apt-get` can't find a package, or a
`find_package()` fails during the build, edit that list and re-run
`make build RELEASE=<release>`.

## CI

`.github/workflows/build.yml` builds every release in a matrix derived from
`make print-releases` (i.e. from `releases.mk`), so it can't drift from a local
`make build-all`. Each `.deb` is uploaded as an artifact.

## Publishing to the shared apt repo

klassy-deb has no version of its own — a release *is* the klassy version pinned as
`REF_<release>` in `releases.mk`. Publishing is **git-tag driven** (only `git`
needed locally — no `gh`): `make tag` derives the tag from `REF` and pushes it,
and `.github/workflows/publish.yml` picks it up.

```sh
make tag RELEASE=debian_sid        # -> pushes tag  debian_sid-v6.7.2
```

On that tag CI builds the `.deb`, attaches it to a GitHub release, then calls
debian-repo's `register` action — which commits `packages/klassy.json` there and
triggers a publish. You never type a version; it comes from `REF_<release>`.

- **New klassy version?** bump `REF_<release>` in `releases.mk`, then
  `make tag RELEASE=<r>`.
- **Re-package the same version** (e.g. a deps fix)? bump `PKGREV_<release>` in
  `releases.mk` (defaults to 1) and re-tag: `make tag RELEASE=<r> FORCE=1` — the
  `.deb` becomes `6.7.2-2~sid`.

(CI builds the `.deb` and uploads it to the GitHub release itself — `gh` runs
only on the runner. Locally you only need `git`.)

**One-time setup** — create a token that can push to `debian-repo` and store it
as the **`DEBIAN_REPO_TOKEN`** secret in this repo:

- Fine-grained PAT (tightest): Resource owner `ansible-autobott`, only the
  `debian-repo` repository, Repository permissions → **Contents: Read and
  write** (enable fine-grained tokens for the org first; approve the request if
  required).
- or a classic PAT with the **`repo`** scope (authorize SSO for
  `ansible-autobott` if enforced).

debian-repo holds one `klassy` per architecture, so publishing a second release
overwrites `packages/klassy.json` — publish a single release, or add per-suite /
per-name publishing if you need all three served at once. The `register` action
is pinned `@v1` (switch to `@main` if debian-repo hasn't tagged `v1` yet).

## Packaging mechanism

Klassy ships no Debian packaging, so the container stages `cmake --install` into
a `DESTDIR` and wraps it with `dpkg-deb`. Runtime `Depends` are currently
minimal — for production-grade packages, add `dpkg-shlibdeps` or author a
proper `debian/` directory.
