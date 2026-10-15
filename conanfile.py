from conan import ConanFile
from conan.errors import ConanException
from conan.tools.cmake import CMake, CMakeDeps, CMakeToolchain, cmake_layout
import os


class JfrogCurationDemo(ConanFile):
    """Application consumer. JFrog Curation runs in Artifactory, not in this recipe."""

    settings = "os", "compiler", "build_type", "arch"
    options = {
        "demo_scenario": ["baseline", "immaturity", "vulnerability", "license"],
    }
    default_options = {
        "demo_scenario": "baseline",
    }

    def configure(self):
        # Header-only spdlog brings in header-only fmt transitively.
        # This avoids platform-specific binaries and source builds.
        self.options["spdlog/*"].header_only = True
        self.options["fmt/*"].header_only = True

    def layout(self):
        cmake_layout(self)

    def requirements(self):
        scenario = str(self.options.demo_scenario)
        path = os.path.join(self.recipe_folder, "scenarios", scenario, "conanfile.txt")
        if not os.path.isfile(path):
            raise ConanException(f"Unknown demo_scenario '{scenario}': {path} does not exist")
        in_requires = False
        with open(path, encoding="utf-8") as handle:
            for raw in handle:
                stripped = raw.strip()
                if stripped.startswith("[") and stripped.endswith("]"):
                    in_requires = stripped == "[requires]"
                    continue
                if not in_requires:
                    continue
                reference = raw.split("#", 1)[0].strip()
                if reference:
                    self.requires(reference)

    def build_requirements(self):
        self.tool_requires("cmake/3.30.5")

    def generate(self):
        scenario = str(self.options.demo_scenario)
        CMakeDeps(self).generate()
        toolchain = CMakeToolchain(self)
        toolchain.cache_variables["DEMO_USE_RAPIDJSON"] = scenario == "vulnerability"
        toolchain.cache_variables["DEMO_USE_CIMG"] = scenario == "license"
        toolchain.cache_variables["DEMO_USE_HTTPLIB"] = scenario in ("immaturity", "vulnerability")
        toolchain.generate()

    def build(self):
        cmake = CMake(self)
        cmake.configure()
        cmake.build()
