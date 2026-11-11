import 'dart:ui';

class FaceObservation {
  const FaceObservation({
    required this.box,
    this.eulerX,
    this.eulerY,
    this.eulerZ,
    this.landmarks = const [],
    this.contours = const [],
    this.trackingId,
  });

  final Rect box;
  final double? eulerX;
  final double? eulerY;
  final double? eulerZ;
  final List<Offset> landmarks;
  final List<List<Offset>> contours;
  final int? trackingId;
}

class FrameAnalysis {
  const FrameAnalysis({
    required this.faces,
    required this.imageSize,
    required this.processingTime,
    required this.timestamp,
    this.meanLuma,
    this.rotationDegrees = 0,
    this.sensorSize,
  });

  final List<FaceObservation> faces;
  final Size imageSize;
  final Duration processingTime;
  final Duration timestamp;
  final double? meanLuma;
  final int rotationDegrees;
  final Size? sensorSize;
}
