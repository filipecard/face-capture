import 'dart:ui';

import '../core/face_observation.dart';
import '../diagnostics/detection_thresholds.dart';

class StabilityTracker {
  FaceObservation? _previous;
  Duration? _stableSince;
  Duration _last = Duration.zero;

  bool get isStable => _stableSince != null;

  Duration get stableFor =>
      _stableSince == null ? Duration.zero : _last - _stableSince!;

  void reset() {
    _previous = null;
    _stableSince = null;
  }

  void update(
    FaceObservation? face,
    Size imageSize,
    Duration timestamp,
    DetectionThresholds t,
  ) {
    _last = timestamp;
    final prev = _previous;
    _previous = face;

    if (face == null || prev == null || imageSize.width <= 0) {
      _stableSince = null;
      return;
    }

    final moved =
        (face.box.center - prev.box.center).distance / imageSize.width;
    final angleDelta = _maxAngleDelta(face, prev);
    final stableNow =
        moved <= t.stabilityMaxMovement &&
        angleDelta <= t.stabilityMaxAngleDelta;

    if (stableNow) {
      _stableSince ??= timestamp;
    } else {
      _stableSince = null;
    }
  }

  static double _maxAngleDelta(FaceObservation a, FaceObservation b) {
    double d(double? x, double? y) =>
        (x == null || y == null) ? double.infinity : (x - y).abs();
    final dx = d(a.eulerX, b.eulerX);
    final dy = d(a.eulerY, b.eulerY);
    final dz = d(a.eulerZ, b.eulerZ);
    return [dx, dy, dz].reduce((m, v) => v > m ? v : m);
  }
}
