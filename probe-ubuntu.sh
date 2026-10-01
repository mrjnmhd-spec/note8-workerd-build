#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
[[ $(getconf GNU_LIBC_VERSION) == 'glibc 2.39' ]]
cd /out
sha256sum --check SHA256SUMS
./workerd-linux-arm64-notcmalloc --version | tee target-version.txt
grep -q '2026-06-25' target-version.txt
ldd ./workerd-linux-arm64-notcmalloc > target-libraries.txt
! grep -q 'not found' target-libraries.txt
mkdir -p /tmp/http-probe
cd /tmp/http-probe
printf "addEventListener('fetch', event => event.respondWith(new Response('NOTE8_UBUNTU_HTTP_OK')));\n" > hello.js
cat > config.capnp <<'CAPNP'
using Workerd = import "/workerd/workerd.capnp";
const config :Workerd.Config = (
  services = [(name = "main", worker = (serviceWorkerScript = embed "hello.js", compatibilityDate = "2025-09-02"))],
  sockets = [(name = "http", address = "127.0.0.1:8080", http = (), service = "main")]
);
CAPNP
/out/workerd-linux-arm64-notcmalloc serve config.capnp > /out/target-http.log 2>&1 &
PROBE_PID=$!
trap 'kill "$PROBE_PID" 2>/dev/null || true; wait "$PROBE_PID" 2>/dev/null || true' EXIT
PASSED=0
for attempt in $(seq 1 30); do
  if curl --fail --silent --max-time 2 http://127.0.0.1:8080/ > response.txt; then
    grep -qx NOTE8_UBUNTU_HTTP_OK response.txt
    PASSED=1
    break
  fi
  kill -0 "$PROBE_PID"
  sleep 1
done
[[ $PASSED == 1 ]]
kill "$PROBE_PID"
wait "$PROBE_PID" || true
trap - EXIT
printf 'ubuntu_glibc_2.39_version_http=PASS\nphone_test=NOT_RUN\n' > /out/target-acceptance.txt
