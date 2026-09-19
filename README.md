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

| Release           | Base image            | Codename | klassy ref (default) |
|-------------------|-----------------------|----------|----------------------|
| `debian13_trixie` | `debian:trixie-slim`  | `trixie` | `v6.5.3`             |
| `debian_testing`  | `debian:testing-slim` | `forky`  | `v6.7.2`             |
| `debian_sid`      | `debian:sid-slim`     | `sid`    | `v6.7.2`             |

All three build the Qt6 / KF6 / KDecoration3 stack.

Each release sets its base image via `IMAGE_<release>` in `releases.mk` — the
release keys are just labels and don't have to match a Docker tag. The **codename**
(`CODENAME_<release>`) is the part that must be real: it becomes the `.deb`'s
version suffix (`~forky`), the `dist/` subdirectory, and the release the apt repo
files the package under. It cannot be inferred from the key — `debian_testing`
targets whatever codename Debian currently calls testing, so when forky is
promoted to stable, `CODENAME_debian_testing` moves to the next one.

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
`dist/<codename>/` (e.g. `dist/forky/`) — both are git-ignored.

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
├── dist/<codename>/*.deb        # (git-ignored) built artifacts
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
`REF_<release>` in `releases.mk`, plus the Debian packaging revision
`PKGREV_<release>` (defaults to 1). Publishing is **git-tag driven** (only `git`
needed locally — no `gh`): `make tag` derives the tag from both and pushes it, and
`.github/workflows/publish.yml` picks it up.

```sh
make tag RELEASE=debian_sid        # -> pushes tag  debian_sid-v6.7.2-1
```

On that tag CI builds the `.deb`, attaches it to a GitHub release, then calls
debian-repo's `register` action — which commits
`packages/klassy.<codename>.json` there and triggers a publish. You never type a
version; it comes from `REF_<release>` and is read back out of the built `.deb`.

All three releases can be served at once, and each publishes independently: a
package file in debian-repo holds one version, so every codename gets its own
file (`klassy.trixie.json`, `klassy.forky.json`, `klassy.sid.json`). Tagging `sid`
never touches trixie's entry, so one suite's broken build cannot block another's
fix. debian-repo merges them into a single `klassy` listing — the only rule is
that no two files claim the same (package, release, arch).

- **New klassy version?** bump `REF_<release>` in `releases.mk` and drop any
  `PKGREV_<release>` line (the revision counts builds of one upstream version, so it
  restarts at 1), commit, then `make tag RELEASE=<r>`.
- **Re-package the same version** (e.g. a deps fix)? bump `PKGREV_<release>` in
  `releases.mk`, commit, then `make tag RELEASE=<r>` — the `.deb` becomes
  `6.7.2-2~sid` and the tag `debian_sid-v6.7.2-2`. No `FORCE` needed: because the
  revision is part of the tag, each re-package gets its own tag, GitHub release and
  asset URL instead of overwriting the previous one's.

Commit the `releases.mk` bump *before* tagging. CI builds the tagged commit and reads
the revision from its `releases.mk`, so `make tag` refuses to run with that file
dirty, and `publish.yml` fails the build if the tag's `-<rev>` and
`PKGREV_<release>` disagree. Passing `PKGREV=2` on the command line is for local
builds (`make build RELEASE=debian_sid PKGREV=2`); a tag pushed that way is rejected.

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

The `register` action is currently used at `@main`, because debian-repo has not
tagged a `v1` yet; re-pin `publish.yml` to `@v1` once it does, to insulate this
repo from format changes.

Note the uploaded asset is named `klassy_6.7.2-1.sid_amd64.deb` — a `.` where the
version has a `~`. **GitHub rewrites `~` to `.` in release asset names** (verified:
uploading `klassy_6.7.2-1~sid_amd64.deb` stores it as `klassy_6.7.2-1.sid_amd64.deb`),
and debian-repo records its download URL from the filename — so emitting the tilde
would 404 every publish. `docker/build-package.sh` therefore does the substitution
itself, keeping the built filename and the asset name identical. The `.deb`'s own
`Version` keeps the tilde, which is what actually matters: apt needs it to rank
`6.7.2-1~sid` below a future `6.7.2-1`. debian-repo re-derives the pooled filename
from the control fields, so what apt serves is unaffected.

## Packaging mechanism

Klassy ships no Debian packaging, so the container stages `cmake --install` into
a `DESTDIR` and wraps it with `dpkg-deb`.

### Runtime dependencies

`Depends` is **generated per build by `dpkg-shlibdeps`**, never hand-written: it
maps every shared library the compiled binaries `NEED` back to the Debian package
providing it, so each suite gets the dependencies of the exact stack it was
compiled against. trixie resolves to `libqt6core6t64 (>= 6.8.2)`, sid to whatever
its newer Qt6 provides — and the versioned floors track upstream automatically.

Three details make this work without debhelper:

- The staging `DESTDIR` is `/tmp/pkg/debian/<package>`, and `DEBIAN/` is created
  *before* `dpkg-shlibdeps` runs. It finds the package root by walking up from
  each binary looking for a `DEBIAN/` directory; without it, every object is
  reported as "should already be installed in their package's directory" and
  treated as living outside the package.
- `debian/shlibs.local` declares klassy's *own* private library
  (`libklassycommon6.so.6`) — no installed package provides it, and
  `dpkg-shlibdeps` fails hard on unknown `NEED`s. The entry is derived from the
  staged `SONAME`s, so it covers both the Qt5 (`…common5`) and Qt6 builds. The
  resulting self-dependency is filtered out of `Depends`.
- `-l` points at the staged library directory so that private library can be read
  from the build tree rather than the system.

Anything not discoverable from ELF headers is declared by hand in
`build-package.sh`: `Recommends: kwin-wayland | kwin-x11, systemsettings` (the
decoration needs a KWin to load it, and systemsettings to select it) and
`Suggests: plasma-desktop`.

Verify a build's dependencies resolve on a clean system with:

```sh
docker run --rm -v "$PWD/dist/trixie:/deb:ro" debian:trixie-slim \
  sh -c 'apt-get update -qq && apt-get install -y --simulate /deb/klassy_*.deb'
```

### Maintainer

`Maintainer` defaults to `Andres Bott <contact@andresbott.com>` in
`docker/build-package.sh`; override per build with `make build DEB_MAINTAINER='…'`.
`Homepage` deliberately stays on upstream klassy — these are unofficial builds,
which the extended description states.
