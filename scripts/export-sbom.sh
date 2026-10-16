#!/usr/bin/env bash
# Export a CycloneDX SBOM from the published Conan package's resolved graph.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
REMOTE="${CONAN_REMOTE_NAME:-demo2-dev-conan}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

if [[ ! "${VERSION}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "Usage: $0 <published-version> [output.cdx.json]" >&2
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
command -v python3 >/dev/null || { echo "Python 3 is required." >&2; exit 1; }

OUTPUT="${2:-${ROOT}/build/sbom/curation-demo-${VERSION}.cdx.json}"
mkdir -p "$(dirname "${OUTPUT}")"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Pin the exact dependency recipe revisions recorded in the published binary.
# A newer revision with the same version can change Conan's package ID.
conan list "curation-demo/${VERSION}:*" -r "${REMOTE}" -f json \
    --out-file="${WORK}/package-list.json" -cc core:non_interactive=True
python3 - "${WORK}/package-list.json" "${WORK}/conan.lock" "${REMOTE}" "${VERSION}" "${BUILD_TYPE}" <<'PY'
import json
import sys

source, target, remote, version, build_type = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    listing = json.load(handle)
recipes = listing.get(remote, {}).get(f"curation-demo/{version}", {}).get("revisions", {})
packages = [(revision, data) for revision, recipe in recipes.items()
            for data in recipe.get("packages", {}).values()
            if data.get("info", {}).get("settings", {}).get("build_type") == build_type]
if len(packages) != 1:
    raise SystemExit(f"Expected one published {build_type} binary for curation-demo/{version}; found {len(packages)}")
revision, package = packages[0]
requires = [f"curation-demo/{version}#{revision}"]
requires.extend(ref.split(":", 1)[0] for ref in package["info"].get("requires", []))
with open(target, "w", encoding="utf-8") as handle:
    json.dump({"version": "0.5", "requires": requires,
               "build_requires": [], "python_requires": []}, handle)
PY

# Resolve the exact published graph through the Conan virtual repository.
conan install --requires="curation-demo/${VERSION}" -r "${REMOTE}" \
    --build=never -s "build_type=${BUILD_TYPE}" \
    --lockfile="${WORK}/conan.lock" --lockfile-partial \
    -d cyclone_1.6 --deployer-folder="${WORK}" -of "${WORK}" \
    -cc core:non_interactive=True

SBOM="${WORK}/sbom-cyclonedx-1.6.json"
python3 - "${SBOM}" "${VERSION}" <<'PY'
import json
import sys

path, version = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    bom = json.load(handle)
components = bom.get("components", [])
app = next((component for component in components
            if component.get("name") == "curation-demo"
            and component.get("version") == version), None)
if app is None:
    raise SystemExit("SBOM does not contain the requested Conan package")
dependencies = next((item for item in bom.get("dependencies", [])
                     if item.get("ref") == app.get("bom-ref")), None)
if not dependencies or not dependencies.get("dependsOn"):
    raise SystemExit("SBOM contains no dependencies for the Conan package")
print("SBOM components:", ", ".join(
    f"{component['name']}/{component['version']}" for component in components))
PY

cp "${SBOM}" "${OUTPUT}"
echo "Exported ${OUTPUT}"
