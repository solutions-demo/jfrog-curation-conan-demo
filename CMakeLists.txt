cmake_minimum_required(VERSION 3.15)
project(jfrog_curation_demo LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS ON)

find_package(spdlog CONFIG REQUIRED)
find_package(nlohmann_json CONFIG REQUIRED)
find_package(magic_enum CONFIG REQUIRED)

add_executable(curation_demo src/main.cpp)
target_link_libraries(curation_demo PRIVATE
    spdlog::spdlog_header_only
    nlohmann_json::nlohmann_json
    magic_enum::magic_enum)

if(DEMO_USE_RAPIDJSON)
    find_package(RapidJSON CONFIG REQUIRED)
    target_link_libraries(curation_demo PRIVATE rapidjson)
    target_compile_definitions(curation_demo PRIVATE DEMO_USE_RAPIDJSON=1)
endif()

if(DEMO_USE_CIMG)
    find_package(cimg CONFIG REQUIRED)
    target_link_libraries(curation_demo PRIVATE cimg::cimg)
    target_compile_definitions(curation_demo PRIVATE DEMO_USE_CIMG=1)
endif()

if(DEMO_USE_HTTPLIB)
    find_package(httplib CONFIG REQUIRED)
    target_link_libraries(curation_demo PRIVATE httplib::httplib)
    target_compile_definitions(curation_demo PRIVATE DEMO_USE_HTTPLIB=1)
endif()

enable_testing()
add_test(NAME run_demo COMMAND curation_demo)
set_tests_properties(run_demo PROPERTIES
    PASS_REGULAR_EXPRESSION "JSON processed successfully")
if(DEMO_USE_RAPIDJSON)
    set_tests_properties(run_demo PROPERTIES PASS_REGULAR_EXPRESSION "\"rapidjson\"")
endif()
if(DEMO_USE_CIMG)
    set_tests_properties(run_demo PROPERTIES PASS_REGULAR_EXPRESSION "cimg_pixels")
endif()
