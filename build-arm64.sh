#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -m) == aarch64 ]] || { echo 'Native ARM64 builder required'; exit 2; }
SOURCE_COMMIT=d3c2d082e29ae710ec94cd87faf0e6d738485275
BAZEL_SHA256=82d1163884e45a6a7ff764cc01197b1b1ed497000726b84dc4b47c1dfc8a2bb4
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git clang-19 lld-19 llvm-19 libc++-19-dev libc++abi-19-dev libclang-rt-19-dev libunwind-19-dev python3 zip unzip tcl nodejs npm pkg-config
mkdir -p /build /out
cd /build
git init source
git -C source remote add origin https://github.com/cloudflare/workerd.git
git -C source fetch --depth 1 origin "$SOURCE_COMMIT"
git -C source checkout --detach FETCH_HEAD
[[ $(git -C source rev-parse HEAD) == "$SOURCE_COMMIT" ]]
curl --fail --location --retry 2 https://github.com/bazelbuild/bazel/releases/download/9.1.1/bazel-9.1.1-linux-arm64 -o /build/bazel
printf '%s  /build/bazel\n' "$BAZEL_SHA256" | sha256sum --check
chmod 755 /build/bazel
cd source
[[ $(cat .bazelversion) == 9.1.1 ]]
printf 'build:linux --repo_env=CC=/usr/lib/llvm-19/bin/clang\nbuild:linux --repo_env=AR=/usr/lib/llvm-19/bin/llvm-ar\nbuild:linux --linkopt=--ld-path=/usr/lib/llvm-19/bin/ld.lld\nbuild:linux --host_linkopt=--ld-path=/usr/lib/llvm-19/bin/ld.lld\n' > /build/builder.bazelrc
/build/bazel --bazelrc=.bazelrc --bazelrc=/build/builder.bazelrc build --config=release_linux --jobs=3 --local_resources=memory=10000 --strip=always --@workerd//src/workerd/server:use_tcmalloc=False //src/workerd/server:workerd
BIN=/build/source/bazel-bin/src/workerd/server/workerd
"$BIN" --version | tee /out/version.txt
grep -q '2026-06-25' /out/version.txt
mkdir /build/http-probe
cd /build/http-probe
cat > hello.js <<'JS'
addEventListener('fetch', event => event.respondWith(new Response('NOTE8_WORKERD_BUILD_HTTP_OK')));
JS
cat > config.capnp <<'CAPNP'
using Workerd = import "/workerd/workerd.capnp";
const config :Workerd.Config = (
  services = [(name = "main", worker = (serviceWorkerScript = embed "hello.js", compatibilityDate = "2025-09-02"))],
  sockets = [(name = "http", address = "127.0.0.1:8080", http = (), service = "main")]
);
CAPNP
"$BIN" serve config.capnp > /out/http-probe.log 2>&1 &
PROBE_PID=$!
trap 'kill "$PROBE_PID" 2>/dev/null || true; wait "$PROBE_PID" 2>/dev/null || true' EXIT
PASSED=0
for attempt in $(seq 1 30); do
  if curl --fail --silent --max-time 2 http://127.0.0.1:8080/ > /build/http-response; then
    grep -qx NOTE8_WORKERD_BUILD_HTTP_OK /build/http-response
    PASSED=1
    break
  fi
  kill -0 "$PROBE_PID"
  sleep 1
done
[[ $PASSED == 1 ]] || exit 3
kill "$PROBE_PID"
wait "$PROBE_PID" || true
trap - EXIT
cp "$BIN" /out/workerd-linux-arm64-notcmalloc
cd /out
sha256sum workerd-linux-arm64-notcmalloc > SHA256SUMS
printf 'source=https://github.com/cloudflare/workerd\ncommit=%s\nversion=1.20260625.1\nallocator=system\nphone_test=NOT_RUN\n' "$SOURCE_COMMIT" > provenance.txt
/build/bazel --version >> provenance.txt
/usr/lib/llvm-19/bin/clang --version >> provenance.txt
/usr/lib/llvm-19/bin/llvm-readelf --program-headers --dynamic --version-info workerd-linux-arm64-notcmalloc > elf-requirements.txt
dpkg-query -W > packages.txt
echo 'NATIVE_ARM64_BUILD_HTTP_PASSED_PHONE_TEST_PENDING'
