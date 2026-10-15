# Conan dependency scenarios

Each directory has a directly installable Conan 2 `conanfile.txt`. Configure the Artifactory Conan virtual as described in the [project installation guide](../README.md), then run:

```bash
cd scenarios/baseline
conan install . -r "$CONAN_REMOTE_NAME"
```

Replace `baseline` with `immaturity`, `vulnerability`, or `license`. These files acquire dependencies; build the C++ application from the project root. The root `conanfile.py` reads the same scenario's `[requires]` section when you select `-o "*:demo_scenario=<scenario>"`.

| Scenario | Direct requirements | Intended policy |
| --- | --- | --- |
| `baseline` | spdlog/1.13.0, xtensor/0.26.0, magic_enum/0.9.6 | No matching Block policy |
| `immaturity` | Baseline plus cpp-httplib/0.56.0 | Package age below 88 days, until roughly December 8, 2026 |
| `vulnerability` | Baseline plus rapidjson/1.1.0 and cpp-httplib/0.18.0 | Catalog CVEs; named policy targets CVE-2024-38517 |
| `license` | Baseline plus cimg/3.3.2 | Catalog license CECILL-2.0 |

Every scenario also resolves `fmt/10.2.1` through spdlog and `xtl/0.8.0`, `xsimd/13.2.0`, and `nlohmann_json/3.11.3` through xtensor. The application uses both spdlog and xtensor. The other two xtensor dependencies are new to this demo; fmt and nlohmann_json appeared in earlier versions. All installs use the Artifactory remote and tool-require `cmake/3.30.5`. Verify Catalog findings, age, and available binaries in your own environment. A direct install may report `Cache` and make no new package download. Run `../../scripts/demo.sh <scenario>` from a scenario directory to use a fresh local cache and only your selected Artifactory remote. The script leaves your normal Conan cache untouched.

As checked in JFrog Catalog on October 15, 2026, `rapidjson/1.1.0` has two Medium CVEs and `cpp-httplib/0.18.0` has one High CVE. The license scenario's `cimg/3.3.2` also has one High CVE. Catalog findings are visible independently of whether your Curation policies block a download.
