import 'package:flutter/foundation.dart';

@immutable
class DetectionThresholds {
  const DetectionThresholds({
    this.ovalCenterX = 0.5,
    this.ovalCenterY = 0.45,
    this.ovalWidthFraction = 0.70,
    this.ovalAspect = 1.30,
    this.centerToleranceX = 0.10,
    this.centerToleranceY = 0.10,
    this.minFaceWidthRatio = 0.38,
    this.maxFaceWidthRatio = 0.70,
    this.frontalMaxX = 10,
    this.frontalMaxY = 10,
    this.frontalMaxZ = 10,
    this.sideMinY = 15,
    this.sideMaxY = 30,
    this.pitchMin = 10,
    this.pitchMax = 25,
    this.holdDurationMs = 700,
    this.stabilityMaxMovement = 0.03,
    this.stabilityMaxAngleDelta = 4,
    this.minLuma = 50,
    this.maxLuma = 220,
    this.yawSignForUserRight = -1,
    this.pitchSignForUp = 1,
  });

  final double ovalCenterX;
  final double ovalCenterY;
  final double ovalWidthFraction;
  final double ovalAspect;

  final double centerToleranceX;
  final double centerToleranceY;

  final double minFaceWidthRatio;
  final double maxFaceWidthRatio;

  final double frontalMaxX;
  final double frontalMaxY;
  final double frontalMaxZ;

  final double sideMinY;
  final double sideMaxY;

  final double pitchMin;
  final double pitchMax;

  final int holdDurationMs;

  final double stabilityMaxMovement;
  final double stabilityMaxAngleDelta;

  final double minLuma;
  final double maxLuma;

  final int yawSignForUserRight;

  final int pitchSignForUp;

  DetectionThresholds copyWith({
    double? ovalCenterX,
    double? ovalCenterY,
    double? ovalWidthFraction,
    double? ovalAspect,
    double? centerToleranceX,
    double? centerToleranceY,
    double? minFaceWidthRatio,
    double? maxFaceWidthRatio,
    double? frontalMaxX,
    double? frontalMaxY,
    double? frontalMaxZ,
    double? sideMinY,
    double? sideMaxY,
    double? pitchMin,
    double? pitchMax,
    int? holdDurationMs,
    double? stabilityMaxMovement,
    double? stabilityMaxAngleDelta,
    double? minLuma,
    double? maxLuma,
    int? yawSignForUserRight,
    int? pitchSignForUp,
  }) {
    return DetectionThresholds(
      ovalCenterX: ovalCenterX ?? this.ovalCenterX,
      ovalCenterY: ovalCenterY ?? this.ovalCenterY,
      ovalWidthFraction: ovalWidthFraction ?? this.ovalWidthFraction,
      ovalAspect: ovalAspect ?? this.ovalAspect,
      centerToleranceX: centerToleranceX ?? this.centerToleranceX,
      centerToleranceY: centerToleranceY ?? this.centerToleranceY,
      minFaceWidthRatio: minFaceWidthRatio ?? this.minFaceWidthRatio,
      maxFaceWidthRatio: maxFaceWidthRatio ?? this.maxFaceWidthRatio,
      frontalMaxX: frontalMaxX ?? this.frontalMaxX,
      frontalMaxY: frontalMaxY ?? this.frontalMaxY,
      frontalMaxZ: frontalMaxZ ?? this.frontalMaxZ,
      sideMinY: sideMinY ?? this.sideMinY,
      sideMaxY: sideMaxY ?? this.sideMaxY,
      pitchMin: pitchMin ?? this.pitchMin,
      pitchMax: pitchMax ?? this.pitchMax,
      holdDurationMs: holdDurationMs ?? this.holdDurationMs,
      stabilityMaxMovement: stabilityMaxMovement ?? this.stabilityMaxMovement,
      stabilityMaxAngleDelta:
          stabilityMaxAngleDelta ?? this.stabilityMaxAngleDelta,
      minLuma: minLuma ?? this.minLuma,
      maxLuma: maxLuma ?? this.maxLuma,
      yawSignForUserRight: yawSignForUserRight ?? this.yawSignForUserRight,
      pitchSignForUp: pitchSignForUp ?? this.pitchSignForUp,
    );
  }
}

class ThresholdsStore extends ChangeNotifier {
  ThresholdsStore([DetectionThresholds initial = const DetectionThresholds()])
    : _value = initial;

  DetectionThresholds _value;
  DetectionThresholds get value => _value;

  set value(DetectionThresholds next) {
    _value = next;
    notifyListeners();
  }

  void reset() => value = const DetectionThresholds();
}

final ThresholdsStore thresholdsStore = ThresholdsStore();
