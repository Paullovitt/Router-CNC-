#include "router_core.h"

#include <cmath>
#include <limits>

const char* rc_core_version() {
  return "router_core/1.0.0-cpp";
}

double rc_estimate_path_time_ms(double distance_mm, double feed_mm_per_min) {
  const double safe_distance = distance_mm > 0.0 ? distance_mm : 0.0;
  const double safe_feed = feed_mm_per_min > 1.0 ? feed_mm_per_min : 1.0;
  return (safe_distance / safe_feed) * 60000.0;
}

int32_t rc_pick_nearest_index(const double* xs,
                              const double* ys,
                              int32_t count,
                              double from_x,
                              double from_y) {
  if (xs == nullptr || ys == nullptr || count <= 0) return -1;

  int32_t best_idx = -1;
  double best_dist_sq = std::numeric_limits<double>::infinity();
  for (int32_t i = 0; i < count; i += 1) {
    const double dx = xs[i] - from_x;
    const double dy = ys[i] - from_y;
    const double dist_sq = (dx * dx) + (dy * dy);
    if (dist_sq < best_dist_sq) {
      best_dist_sq = dist_sq;
      best_idx = i;
    }
  }
  return best_idx;
}
