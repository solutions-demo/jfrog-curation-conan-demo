#include <fmt/core.h>
#include <magic_enum.hpp>
#include <nlohmann/json.hpp>

#include <iostream>
#include <string>

#if defined(DEMO_USE_RAPIDJSON)
#include <rapidjson/document.h>
#endif

#if defined(DEMO_USE_CIMG)
#define cimg_display 0
#include <CImg.h>
#endif

#if defined(DEMO_USE_HTTPLIB)
#include <httplib.h>
#endif

namespace {

enum class DemoStatus { Complete };

}  // namespace

int main() {
    const std::string status{magic_enum::enum_name(DemoStatus::Complete)};
    nlohmann::json body = {
        {"customer", "JFrog Curation demo"},
        {"fmt", fmt::format("{}.{}.{}", FMT_VERSION / 10000, (FMT_VERSION / 100) % 100, FMT_VERSION % 100)},
        {"message", "JSON processed successfully"},
    };

#if defined(DEMO_USE_RAPIDJSON)
    const std::string encoded = body.dump();
    rapidjson::Document document;
    document.Parse(encoded.c_str());
    if (document.HasParseError() || !document.HasMember("message") || !document["message"].IsString()) {
        return 1;
    }
    body["rapidjson"] = std::string(document["message"].GetString());
#endif

#if defined(DEMO_USE_CIMG)
    cimg_library::CImg<unsigned char> image(4, 4, 1, 1, 0);
    image.fill(7);
    body["cimg_pixels"] = image.width() * image.height();
#endif

#if defined(DEMO_USE_HTTPLIB)
    httplib::Request request;
    request.method = "GET";
    request.path = "/curation";
    body["httplib_path"] = request.path;
#endif

    std::cout << fmt::format("JFrog Curation demo [{}]: {}\n", status, body.dump());
    return 0;
}
