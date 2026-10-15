# JFrog Curation demo for Conan 2

This C++17 application resolves real Conan packages through an Artifactory Conan virtual repository. JFrog Curation governs the underlying remote. The demo has a passing baseline and three blocking scenarios: immaturity, a named CVE, and a license. The application does not simulate Curation decisions.

This guide is for an operator installing the demo in **their own JFrog environment**. Replace the example repository keys and URL. Policy IDs and audit events are specific to each instance.

The project root contains the Conan consumer recipe (`conanfile.py`), CMake application (`CMakeLists.txt` and `src/main.cpp`), scenario manifests under `scenarios/`, and the fresh-download runner `scripts/demo.sh`.

## 1. Prerequisites

- JFrog Platform with Artifactory and Curation, and permission to create repositories, conditions, and policies. Check the [Conan row in JFrog's support matrix](https://docs.jfrog.com/security/docs/supported-technologies) for minimum self-managed versions.
- Conan 2, Bash, and a C++17 compiler. The reference run used Conan 2.33.0 and Apple Clang 21 on macOS arm64.
- A default Conan profile. The recipe tool-requires `cmake/3.30.5`; Artifactory must be able to serve a binary for your platform.

The [support matrix](https://docs.jfrog.com/security/docs/supported-technologies) lists Conan Curation service support, but Conan CLI `curation-audit` is “Coming soon” and [Compliant Version Selection](https://docs.jfrog.com/security/docs/compliant-version-selection) does not list Conan. This demo therefore uses policy blocks and Curation **Downloads** audit events. It has no Conan CVS scenario.

## 2. Create and connect repositories

In **Administration → Repositories**, create a Conan **remote** repository and a Conan **virtual** repository that contains it. Keep this virtual limited to one public-source remote for predictable results.

| Setting | Example |
| --- | --- |
| Remote repository key | `demo-conan-remote` |
| Virtual repository key | `demo-conan-virtual` |
| Upstream URL in the Artifactory remote | `https://center2.conan.io` |
| JFrog platform URL | `https://example.jfrog.io` |

The **Conan client** must use only `https://example.jfrog.io/artifactory/api/conan/demo-conan-virtual`. Artifactory uses its remote repository to contact Conan Center. See [Artifactory Conan repositories](https://docs.jfrog.com/artifactory/docs/conan-repositories) for the repository and client URL formats.

JFrog's published Curation [support matrix](https://docs.jfrog.com/security/docs/supported-technologies) still names `http://center.conan.io/` for Conan, whereas the reference instance used `https://center2.conan.io` to obtain current recipes. Validate Curation support for the `center2` upstream on your JFrog version and confirm a real Downloads audit event before presenting the demo. Do not configure either Conan Center URL as a Conan client remote.

In **Administration → Curation → Remote Repositories**, select Conan and connect the **remote repository key**. Curation policies apply to this remote even when clients use the virtual. Keep Artifactory's remote cache enabled; JFrog recommends at least 30 days. [Connection guide](https://docs.jfrog.com/security/docs/connect-remote-repositories-to-curation).

## 3. Create the conditions and policies

Inspect existing global and repository policies first. Global policies can also block these packages. In **Administration → Curation → Conditions**, create:

| Condition name | Template | Value |
| --- | --- | --- |
| `Conan Demo - Immaturity 88 Days` | Package version is immature (`isImmature`) | `package_age_days = 88`; leave optional CVSS relaxation unset |
| `Conan Demo - CVE-2024-38517` | Package Vulnerable to a Specific CVE (`CVEName`) | `cve_name = CVE-2024-38517` |
| `Conan Demo - CeCILL 2.0` | Block list by License (`BannedLicenses`) | Ban `CECILL-2.0`; set multiple-license permissive approach to `false` |

In **Application → Curation → Policies**, create one policy per condition. Use the same name and set:

| Policy setting | Value |
| --- | --- |
| Scope | **Specific repositories**: the Conan **remote** key, not the virtual key |
| Condition | The matching condition above |
| Action | **Block**, not Dry Run |
| Cached packages | **Enforce Policy on Cached Packages** |
| Pending Catalog update | **Skip** for this demo |
| Waiver requests | **Forbidden** for this demo |
| Federation sharing | **Disabled**, unless your environment requires it |

Cached-package blocking also needs the platform setting **Administration → Curation → General → Enable Curation for Cached Packages**. Both the platform setting and policy toggle are required. [Cached-package enforcement](https://docs.jfrog.com/security/docs/block-downloads-from-cached-remote-repositories), [condition API](https://docs.jfrog.com/security/reference/createcondition), [policy API](https://docs.jfrog.com/security/reference/createpolicy).

Before saving the CVE and license conditions, verify that your JFrog Catalog currently reports `CVE-2024-38517` for `rapidjson/1.1.0` and `CECILL-2.0` for `cimg/3.3.2`. Catalog findings can change. The license package also had a reported CVE, so inspect the audit policy name: another vulnerability policy might be its actual blocker.

JFrog also offers a malicious-package condition. This project intentionally contains no known malicious dependency. You can configure that condition separately and show a real audit event from your environment; do not add malware to the demo merely to force a block.

## 4. Configure Conan on the demo machine

Clone the repository, then set your own values:

```bash
git clone https://github.com/solutions-demo/jfrog-curation-conan-demo.git
cd jfrog-curation-conan-demo
export JFROG_BASE_URL=https://example.jfrog.io
export CONAN_VIRTUAL_REPO=demo-conan-virtual
export CONAN_REMOTE_NAME=artifactory
conan profile detect
conan remote add "$CONAN_REMOTE_NAME" \
  "$JFROG_BASE_URL/artifactory/api/conan/$CONAN_VIRTUAL_REPO"
conan remote login "$CONAN_REMOTE_NAME"
conan remote list
```

`JFROG_BASE_URL` is the HTTPS platform URL without `/artifactory` or another path. `CONAN_VIRTUAL_REPO` is the virtual key; `CONAN_REMOTE_NAME` is a local alias and defaults to `artifactory` in the script. If the alias exists, use `conan remote update "$CONAN_REMOTE_NAME" --url "<Artifactory Conan virtual URL>"` instead of adding it. Authenticate using your normal JFrog method; never put a token in this project.

For a strict Artifactory-only normal Conan configuration, remove the default direct remote:

```bash
conan remote remove conancenter
conan remote list
```

The demo script leaves your normal Conan configuration unchanged. Its temporary Conan home contains **only** the selected Artifactory remote, so it cannot fall back to direct Conan Center access.

## 5. Run the scenarios

```bash
./scripts/demo.sh baseline       # Expected: succeeds
./scripts/demo.sh immaturity     # Expected: cpp-httplib/0.56.0 blocked while immature
./scripts/demo.sh vulnerability  # Expected: rapidjson/1.1.0 blocked by named CVE
./scripts/demo.sh license        # Expected: cimg/3.3.2 blocked by license
```

| Scenario | Direct application requirements | Audit focus |
| --- | --- | --- |
| `baseline` | `spdlog/1.13.0`, `xtensor/0.26.0`, `magic_enum/0.9.6` | Allowed, provided no other policy matches |
| `immaturity` | Baseline plus `cpp-httplib/0.56.0` | The 88-day policy |
| `vulnerability` | Baseline plus `rapidjson/1.1.0` | The named-CVE policy |
| `license` | Baseline plus `cimg/3.3.2` | The license policy |

Every scenario also tool-requires `cmake/3.30.5`. `scripts/demo.sh` copies Conan authentication and profile data into a temporary home, removes all other client remotes there, and uses fresh package and download caches. It leaves `~/.conan2` untouched and writes logs to `demo-logs/`. A successful run requires a `Downloaded (<remote name>)` line and rejects locally cached dependencies. A policy block makes the script exit nonzero. The script does not clear **Artifactory's** remote cache; the policy setting in step 3 governs packages served from it.

The immaturity example is time-sensitive. `cpp-httplib/0.56.0` was published September 11, 2026 and reaches 88 days of age around December 8, 2026. After that, choose a newer version visible in your Catalog, update `scenarios/immaturity/conanfile.txt`, and verify its age. If you also want to build that variant, check its C++ API compatibility.

Do **not** use `--build=missing` during policy demonstrations. A source build can fetch upstream material outside Artifactory after Conan receives a recipe. The reference instance served the selected header-only packages and CMake binary for macOS arm64; verify binary availability for your platform.

Each scenario also has a directly installable `conanfile.txt`:

```bash
cd scenarios/baseline
conan install . -r "$CONAN_REMOTE_NAME"
```

The scenario files list `xtensor/0.26.0` directly. It brings in three **transitive dependencies**: `xtl/0.8.0`, `xsimd/13.2.0`, and `nlohmann_json/3.11.3`. The first two were absent from earlier versions of this demo. `spdlog/1.13.0` also brings in `fmt/10.2.1`. The C++ application computes a value with xtensor and logs its JSON result with spdlog, so these are real application dependencies. All four indirect packages have downloadable binaries for the reference Mac profile; the demo uses `--build=never` and a fresh local cache to exercise Artifactory.

If that reports `Cache`, no new package download occurred. Run `../../scripts/demo.sh baseline` to force a fresh local request. Scenario files acquire dependencies; build the C++ application from the project root:

```bash
cd ../..
conan install . -r "$CONAN_REMOTE_NAME" --build=never
conan build . -r "$CONAN_REMOTE_NAME" --build=never
./build/Release/curation_demo
```

For an allowed variant, pass `-o "*:demo_scenario=<scenario>"` to both `conan install` and `conan build`. The root `conanfile.py` reads that scenario's dependency file.

## 6. Verify decisions

Open **Application → Curation → Audit Events → Downloads**. Filter by time, Conan package, version, and the underlying **remote repository** key. Match the event's action and policy to the terminal request. Conan can report `Binary package not found` for a blocked binary, so that error alone does not establish the cause. No audit event does not prove approval: check the remote connection, policy scope, cache enforcement, and other applicable repositories.

The [Downloads audit API](https://docs.jfrog.com/security/reference/getauditpackages) is another read-only option. Do not use `jf curation-audit` to validate Conan; JFrog currently lists that CLI integration as [coming soon](https://docs.jfrog.com/security/docs/supported-technologies).

| Symptom | Check |
| --- | --- |
| Baseline fails | Read the package and policy in Downloads audit; inspect global policies and binary availability. |
| A blocking scenario succeeds | Check Catalog finding or age, Block versus Dry Run, connection, remote-key scope, waivers, and both cache toggles. |
| `Binary package not found` | Check for a matching Downloads audit block before concluding the binary is absent. |
| No `Downloaded` line | Use `scripts/demo.sh` to avoid the local Conan cache. |
| Authentication error | Log in again to the selected Artifactory Conan remote in your normal Conan home. |
| Direct Conan Center request | Inspect `conan remote list` and manual commands; the script removes other remotes from its temporary home. |

## Reference-instance observations

On October 9, 2026, the original environment used virtual `demo2-dev-conan` and a curated remote pointing to `https://center2.conan.io`. Its fresh-cache baseline succeeded. The immaturity scenario was blocked on `cpp-httplib/0.56.0` in Downloads audit event `497637` by `Immaturity88` and a global immature-package policy. The license scenario was blocked on `cimg/3.3.2` by `CECILL20` in event `497598`. These names and IDs are **not installation values** for another environment. The named-CVE scenario has a Catalog finding but no verified policy block in the reference record; validate its block in your own audit before claiming it.
