#!/usr/bin/env bash
# Package the binary produced by conan build and deploy through the Conan virtual remote.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO="${1:-baseline}"
VERSION="${2:-}"
REMOTE="${CONAN_REMOTE_NAME:-demo2-dev-conan}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

case "${SCENARIO}" in
    baseline|immaturity|vulnerability|license) ;;
    *) echo "Usage: $0 [baseline|immaturity|vulnerability|license] <version>" >&2; exit 2 ;;
esac
if [[ ! "${VERSION}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "Provide a new Conan package version, for example: $0 baseline 0.1.2" >&2
    exit 2
fi
if [[ ! "${REMOTE}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "CONAN_REMOTE_NAME must be a simple remote name." >&2
    exit 2
fi
if [[ ! "${BUILD_TYPE}" =~ ^(Release|Debug|RelWithDebInfo|MinSizeRel)$ ]]; then
    echo "Invalid BUILD_TYPE: ${BUILD_TYPE}" >&2
    exit 2
fi
command -v conan >/dev/null || { echo "Conan 2 is required." >&2; exit 1; }

# Conan resolves dependencies through the existing virtual remote.
conan build "${ROOT}" -r "${REMOTE}" --build=never \
    -o "*:demo_scenario=${SCENARIO}" -s "build_type=${BUILD_TYPE}" \
    -cc core:non_interactive=True

EXE="${ROOT}/build/${BUILD_TYPE}/curation_demo"
if [[ ! -f "${EXE}" || ! -x "${EXE}" ]]; then
    echo "Expected executable not found: ${EXE}" >&2
    exit 1
fi

# export-pkg runs package() on the binary just built in the project folder.
conan export-pkg "${ROOT}" --name=curation-demo --version="${VERSION}" -nr \
    -o "*:demo_scenario=${SCENARIO}" -s "build_type=${BUILD_TYPE}" \
    -cc core:non_interactive=True
conan upload "curation-demo/${VERSION}" -c -r "${REMOTE}" --check \
    -cc core:non_interactive=True
echo "Published Conan package curation-demo/${VERSION} through ${REMOTE}"
