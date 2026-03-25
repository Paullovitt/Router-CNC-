import "dart:typed_data";

import "package:app_flutter/src/native/router_core.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("fallback estima tempo de percurso em ms", () {
    final ms = RouterCoreFallback.estimatePathTimeMs(1800, 1800);
    expect(ms, closeTo(60000, 0.001));
  });

  test("fallback encontra ponto mais proximo", () {
    final xs = Float64List.fromList([0, 100, 210, -20]);
    final ys = Float64List.fromList([0, 100, 30, -15]);

    final idx = RouterCoreFallback.pickNearestIndex(xs, ys, 205, 25);
    expect(idx, 2);
  });
}
