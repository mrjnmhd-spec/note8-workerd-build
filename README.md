# Note8-compatible workerd build

Builds official Cloudflare workerd source at commit d3c2d082e29ae710ec94cd87faf0e6d738485275 (version 1.20260625.1) with the existing use_tcmalloc=False option. This avoids the stock allocator's 48-bit virtual-address-space assumption for a device using a 39-bit kernel.

This repository contains only a generic build recipe. It contains no application source, credentials, database or device data. It is not an official Cloudflare binary distribution.

Manually dispatch Build official workerd for Note8. It uses a standard native ARM64 runner, source/tool/image pins, and mandatory version/HTTP tests in both the builder and Ubuntu 24.04 with glibc 2.39. Successful artifacts include checksums, provenance, installed package versions and ELF requirements. No artifact is uploaded on build or probe failure.

A passing CI build does not establish compatibility with an Android host kernel. Actual device version, HTTP/isolate and storage-binding tests remain required. Build dependencies are downloaded from official vendor registries and signed distribution repositories; distribution package versions are recorded rather than fully snapshot-pinned.

Sources:
- https://github.com/cloudflare/workerd/tree/d3c2d082e29ae710ec94cd87faf0e6d738485275
- https://github.com/cloudflare/workerd/issues/5020
- https://docs.github.com/en/actions/reference/runners/github-hosted-runners