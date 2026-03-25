cmake_minimum_required(VERSION 3.14)
project(router_core LANGUAGES CXX)

add_library(router_core SHARED
  "router_core.cpp"
)

apply_standard_settings(router_core)
target_compile_definitions(router_core PRIVATE ROUTER_CORE_EXPORTS)
target_include_directories(router_core PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
