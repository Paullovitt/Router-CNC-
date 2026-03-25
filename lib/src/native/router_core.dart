import "dart:ffi" as ffi;
import "dart:io";
import "dart:math";
import "dart:typed_data";

import "package:ffi/ffi.dart";

typedef _RcCoreVersionNative = ffi.Pointer<Utf8> Function();
typedef _RcCoreVersionDart = ffi.Pointer<Utf8> Function();

typedef _RcEstimatePathTimeNative = ffi.Double Function(ffi.Double, ffi.Double);
typedef _RcEstimatePathTimeDart = double Function(double, double);

typedef _RcPickNearestIndexNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Double>,
      ffi.Pointer<ffi.Double>,
      ffi.Int32,
      ffi.Double,
      ffi.Double,
    );
typedef _RcPickNearestIndexDart =
    int Function(
      ffi.Pointer<ffi.Double>,
      ffi.Pointer<ffi.Double>,
      int,
      double,
      double,
    );

class RouterCoreNative {
  RouterCoreNative._(ffi.DynamicLibrary lib)
    : _coreVersion = lib
          .lookupFunction<_RcCoreVersionNative, _RcCoreVersionDart>(
            "rc_core_version",
          ),
      _estimatePathTimeMs = lib
          .lookupFunction<_RcEstimatePathTimeNative, _RcEstimatePathTimeDart>(
            "rc_estimate_path_time_ms",
          ),
      _pickNearestIndex = lib
          .lookupFunction<_RcPickNearestIndexNative, _RcPickNearestIndexDart>(
            "rc_pick_nearest_index",
          );

  final _RcCoreVersionDart _coreVersion;
  final _RcEstimatePathTimeDart _estimatePathTimeMs;
  final _RcPickNearestIndexDart _pickNearestIndex;

  static RouterCoreNative? _instance;
  static Object? _loadError;

  static RouterCoreNative? tryInstance() {
    if (_instance != null) return _instance;
    if (_loadError != null) return null;
    try {
      final lib = _openLibrary();
      _instance = RouterCoreNative._(lib);
      return _instance;
    } catch (error) {
      _loadError = error;
      return null;
    }
  }

  static ffi.DynamicLibrary _openLibrary() {
    if (Platform.isWindows) return ffi.DynamicLibrary.open("router_core.dll");
    if (Platform.isLinux) return ffi.DynamicLibrary.open("librouter_core.so");
    if (Platform.isMacOS) {
      return ffi.DynamicLibrary.open("librouter_core.dylib");
    }
    throw UnsupportedError("Plataforma sem suporte para router_core nativo.");
  }

  static String describeLoadError() {
    if (_loadError == null) return "";
    return "Falha ao carregar router_core nativo: $_loadError";
  }

  String coreVersion() => _coreVersion().toDartString();

  double estimatePathTimeMs(double distanceMm, double feedMmPerMin) {
    return _estimatePathTimeMs(distanceMm, feedMmPerMin);
  }

  int pickNearestIndex(
    Float64List xs,
    Float64List ys,
    double fromX,
    double fromY,
  ) {
    final count = min(xs.length, ys.length);
    if (count <= 0) return -1;
    final xPtr = calloc<ffi.Double>(count);
    final yPtr = calloc<ffi.Double>(count);
    try {
      for (var i = 0; i < count; i += 1) {
        xPtr[i] = xs[i];
        yPtr[i] = ys[i];
      }
      return _pickNearestIndex(xPtr, yPtr, count, fromX, fromY);
    } finally {
      calloc.free(xPtr);
      calloc.free(yPtr);
    }
  }
}

class RouterCoreFallback {
  static String coreVersion() => "router_core(fallback)";

  static double estimatePathTimeMs(double distanceMm, double feedMmPerMin) {
    final safeDistance = max(0, distanceMm);
    final safeFeed = max(1, feedMmPerMin);
    return (safeDistance / safeFeed) * 60000.0;
  }

  static int pickNearestIndex(
    Float64List xs,
    Float64List ys,
    double fromX,
    double fromY,
  ) {
    final count = min(xs.length, ys.length);
    if (count <= 0) return -1;
    var bestIdx = 0;
    var bestDistSq = double.infinity;
    for (var i = 0; i < count; i += 1) {
      final dx = xs[i] - fromX;
      final dy = ys[i] - fromY;
      final distSq = (dx * dx) + (dy * dy);
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        bestIdx = i;
      }
    }
    return bestIdx;
  }
}
