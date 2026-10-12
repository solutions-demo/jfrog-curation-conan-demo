#!/usr/bin/env bash
# Install one scenario through an Artifactory Conan virtual, using a throwaway Conan home.
# The original ~/.conan2 cache and remotes are not modified.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO="${1:-baseline}"
: "${JFROG_BASE_URL:?Set JFROG_BASE_URL to your HTTPS JFrog platform URL.}"
: "${CONAN_VIRTUAL_REPO:?Set CONAN_VIRTUAL_REPO to your Conan virtual repository key.}"
REMOTE="${CONAN_REMOTE_NAME:-artifactory}"
JFROG_BASE_URL="${JFROG_BASE_URL%/}"
if [[ ! "${JFROG_BASE_URL}" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
    echo "JFROG_BASE_URL must be an HTTPS platform URL without a path." >&2
    exit 2
fi
if [[ ! "${CONAN_VIRTUAL_REPO}" =~ ^[A-Za-z0-9._-]+$ || ! "${REMOTE}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "CONAN_VIRTUAL_REPO and CONAN_REMOTE_NAME must be simple repository/remote names." >&2
    exit 2
fi
REMOTE_URL="${JFROG_BASE_URL}/artifactory/api/conan/${CONAN_VIRTUAL_REPO}"
SOURCE_HOME="${CURATION_DEMO_SOURCE_CONAN_HOME:-${HOME}/.conan2}"

case "${SCENARIO}" in
    baseline|immaturity|vulnerability|license) ;;
    *)
        echo "Usage: $0 [baseline|immaturity|vulnerability|license]" >&2
        exit 2
        ;;
esac

if [[ ! -f "${SOURCE_HOME}/.conan.db" || ! -f "${SOURCE_HOME}/remotes.json" || ! -f "${SOURCE_HOME}/profiles/default" ]]; then
    echo "Need an authenticated Conan home with a default profile in ${SOURCE_HOME}." >&2
    echo "Create the profile with: conan profile detect" >&2
    echo "Add and log in to ${REMOTE_URL} as ${REMOTE} in your normal Conan home first." >&2
    exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/conan-curation.XXXXXX")"
WORK="$(cd "${WORK}" && pwd -P)"
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

export CONAN_HOME="${WORK}/conan-home"
PACKAGE_CACHE="${WORK}/package-cache"
DOWNLOAD_CACHE="${WORK}/download-cache"
mkdir -p "${CONAN_HOME}" "${PACKAGE_CACHE}" "${DOWNLOAD_CACHE}"
cp "${SOURCE_HOME}/.conan.db" "${SOURCE_HOME}/remotes.json" "${CONAN_HOME}/"
for file in global.conf settings.yml version.txt; do
    [[ ! -f "${SOURCE_HOME}/${file}" ]] || cp "${SOURCE_HOME}/${file}" "${CONAN_HOME}/"
done
cp -R "${SOURCE_HOME}/profiles" "${CONAN_HOME}/"
[[ ! -d "${SOURCE_HOME}/extensions" ]] || cp -R "${SOURCE_HOME}/extensions" "${CONAN_HOME}/"

# Run outside the project tree so a project .conanrc cannot override CONAN_HOME.
cd "${WORK}"
ACTUAL_HOME="$(conan config home)"
if [[ "${ACTUAL_HOME}" != "${CONAN_HOME}" ]]; then
    echo "Conan is using ${ACTUAL_HOME}, expected fresh home ${CONAN_HOME}. Aborting." >&2
    exit 1
fi
if ! conan remote list | grep -Fq "${REMOTE}: ${REMOTE_URL} ["; then
    echo "The source Conan home must contain remote ${REMOTE} at ${REMOTE_URL}." >&2
    echo "Configure and log in to this exact Artifactory remote before running the demo." >&2
    exit 1
fi
# The disposable home may contain other remotes; keep only the selected Artifactory URL.
while IFS= read -r configured_remote; do
    [[ "${configured_remote}" == "${REMOTE}" ]] || conan remote remove "${configured_remote}" >/dev/null
done < <(conan remote list | awk -F': ' '{print $1}')
conan remote enable "${REMOTE}" >/dev/null

mkdir -p "${ROOT}/demo-logs"
LOG="${ROOT}/demo-logs/$(date +%Y%m%d-%H%M%S)-${SCENARIO}.log"

if {
    echo "Scenario: ${SCENARIO}"
    echo "Remote: ${REMOTE} (${REMOTE_URL})"
    echo "Isolated Conan home: ${CONAN_HOME}"
    echo "Isolated package cache: ${PACKAGE_CACHE}"
    echo "Isolated download cache: ${DOWNLOAD_CACHE}"
    echo "Requires:"
    awk '/^\[requires\]$/ { active=1; next } /^\[/ { active=0 } active && $0 !~ /^[[:space:]]*(#|$)/ { print "  " $0 }' "${ROOT}/scenarios/${SCENARIO}/conanfile.txt"
    echo
    conan install "${ROOT}" \
        -r "${REMOTE}" \
        -o "*:demo_scenario=${SCENARIO}" \
        --build=never \
        -cc "core.cache:storage_path=${PACKAGE_CACHE}" \
        -cc "core.download:download_cache=${DOWNLOAD_CACHE}" \
        -cc core:non_interactive=True
} 2>&1 | tee "${LOG}"; then
    :
else
    echo "Install failed. Log: ${LOG}" >&2
    echo "If Conan reports 'Binary package not found', check Curation Audit Events for a blocked download before concluding the binary is absent." >&2
    exit 1
fi

if ! grep -q "Downloaded (${REMOTE})" "${LOG}"; then
    echo "conan install did not download from ${REMOTE}. See ${LOG}." >&2
    exit 1
fi
if grep -Eq '^[[:space:]]+[^[:space:]]+ - Cache$' "${LOG}"; then
    echo "At least one dependency was served from a local cache. See ${LOG}." >&2
    exit 1
fi
echo "Log: ${LOG}"
if [[ "${SCENARIO}" == "baseline" ]]; then
    echo "Baseline passed. To test the 88-day policy, run: ${ROOT}/scripts/demo.sh immaturity"
fi
