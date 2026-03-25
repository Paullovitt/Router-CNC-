#pragma once

#include <cstdint>

#if defined(_WIN32)
#if defined(ROUTER_CORE_EXPORTS)
#define ROUTER_CORE_API __declspec(dllexport)
#else
#define ROUTER_CORE_API __declspec(dllimport)
#endif
#else
#define ROUTER_CORE_API
#endif

extern "C" {

ROUTER_CORE_API const char* rc_core_version();

ROUTER_CORE_API double rc_estimate_path_time_ms(double distance_mm, double feed_mm_per_min);

ROUTER_CORE_API int32_t rc_pick_nearest_index(
    const double* xs,
    const double* ys,
    int32_t count,
    double from_x,
    double from_y);

}
