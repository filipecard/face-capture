import 'dart:ui';

import 'package:face_capture_lab/core/face_observation.dart';
import 'package:face_capture_lab/diagnostics/detection_thresholds.dart';

/// Dados sintéticos para exercitar a lógica sem câmera física.
/// Não representam medições biométricas reais.

const Size kFrameSize = Size(720, 1280);

FrameAnalysis frame(
  List<FaceObservation> faces, {
  double? luma = 128,
  Duration timestamp = Duration.zero,
}) => FrameAnalysis(
  faces: faces,
  imageSize: kFrameSize,
  processingTime: const Duration(milliseconds: 20),
  timestamp: timestamp,
  meanLuma: luma,
);

/// Rosto com centro deslocado de (dx, dy) — fração do quadro — em relação
/// ao centro padrão da moldura, e largura [widthRatio] × largura do quadro.
FaceObservation centeredFace({
  double dx = 0,
  double dy = 0,
  double widthRatio = 0.5,
  double x = 0,
  double y = 0,
  double z = 0,
  DetectionThresholds t = const DetectionThresholds(),
}) {
  final w = kFrameSize.width * widthRatio;
  return FaceObservation(
    box: Rect.fromCenter(
      center: Offset(
        kFrameSize.width * (t.ovalCenterX + dx),
        kFrameSize.height * (t.ovalCenterY + dy),
      ),
      width: w,
      height: w * 1.2,
    ),
    eulerX: x,
    eulerY: y,
    eulerZ: z,
  );
}
