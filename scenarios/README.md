# Conan dependency scenarios

Each directory has a directly installable Conan 2 `conanfile.txt`. Configure the Artifactory Conan virtual as described in the [project installation guide](../README.md), then run:

```bash
cd scenarios/baseline
conan install . -r "$CONAN_REMOTE_NAME"
```

Replace `baseline` with `immaturity`, `vulnerability`, or `license`. These files acquire dependencies; build the C++ application from the project root. The root `conanfile.py` reads the same scenario's `[requires]` section when you select `-o "*:demo_scenario=<scenario>"`.

| Scenario | Direct requirements | Intended policy |
| --- | --- | --- |
| `baseline` | spdlog/1.13.0, nlohmann_json/3.11.3, magic_enum/0.9.6 | No matching Block policy |
| `immaturity` | Baseline plus cpp-httplib/0.56.0 | Package age below 88 days, until roughly December 8, 2026 |
| `vulnerability` | Baseline plus rapidjson/1.1.0 | Named CVE-2024-38517 |
| `license` | Baseline plus cimg/3.3.2 | Catalog license CECILL-2.0 |

Every scenario also resolves `fmt/10.2.1` transitively through `spdlog/1.13.0` and tool-requires `cmake/3.30.5`. The application links to spdlog and uses it to format its output. Verify Catalog findings, age, and available binaries in your own environment. A direct install may report `Cache` and make no new package download. Run `../../scripts/demo.sh <scenario>` from a scenario directory to use a fresh local cache and only your selected Artifactory remote. The script leaves your normal Conan cache untouched.
