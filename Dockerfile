# Docker image for CI (PLAN row 12, discussion #1 ask 2) — the pinned
# toolchain + prebuilt hyb + the runtime, so CI jobs can `container: image`
# or `docker run ... hyb build ...` with zero setup.
#
# Layout (the contract inside the image):
#   /usr/local/bin/hyb                 the CLI (release build)
#   /opt/hybrid/runtime/go/...         the Go binding packages
#   /opt/hybrid/runtime/rust/hyrt/...  bridge sources (contrib path)
#   /opt/hybrid/runtime/rust/hyrt/target/release/libhyrt.a
#          ^^^ PREBUILT staticlib, mtime >= every source — the freshness
#              check in hyb's ensure_staticlib() reuses it; no Rust
#              toolchain is needed at RUN time (only for rebuilding hyrt).
#   ENV HYB_RUNTIME_DIR=/opt/hybrid/runtime — the discovery override
#              (exe-relative /usr/local/bin/runtime does not exist, and the
#              compile-time CARGO_MANIFEST_DIR fallback never survives into
#              an image — the row-16 lesson makes ENV the right wiring).
#
# Pins are the contract: rust:1.99.0 + golang:1.26.9 (HYB-E9001 enforces at
# run time; the image must not introduce drift).

# --- stage 1: everything cargo builds (hyb CLI + the hyrt staticlib) ---
FROM rust:1.99.0-slim-bookworm AS build
WORKDIR /src
COPY compiler/ compiler/
COPY runtime/ runtime/
# The pins are enforced by the images themselves; skip hyb's runtime pin
# check inside cargo builds (no Go here — E9001 checks run when hyb BUILDS
# programs, and stage 2's Go is pinned to 1.26.9).
RUN cd compiler && CARGO_BUILD_JOBS=2 cargo build --release -p hyb --quiet \
 && cd ../runtime/rust/hyrt && CARGO_BUILD_JOBS=2 cargo build --release --quiet

# --- stage 2: the image users get (go toolchain + hyb + runtime) ---
FROM golang:1.26.9-bookworm
COPY --from=build /src/compiler/target/release/hyb /usr/local/bin/hyb
COPY --from=build /src/runtime /opt/hybrid/runtime
# The freshness contract: the shipped lib must be >= every source's mtime
# (the copy preserves source mtimes; touch the lib last — same as
# tools/package_release.sh).
RUN mkdir -p /opt/hybrid/runtime/rust/hyrt/target/release \
 && touch $(find /opt/hybrid/runtime/rust/hyrt -name 'target' -prune -o -type f -print) \
 && touch /opt/hybrid/runtime/rust/hyrt/target/release/libhyrt.a \
 && chmod +x /usr/local/bin/hyb
ENV HYB_RUNTIME_DIR=/opt/hybrid/runtime
# gofmt lives in the Go toolchain (hyb generate emits canonical files);
# CGO is on (bridge programs link libhyrt.a through cgo).
ENV GOFLAGS=-p=2
WORKDIR /work
