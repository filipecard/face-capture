import 'package:flutter/material.dart';

import '../../core/face_observation.dart';
import '../../diagnostics/detection_thresholds.dart';
import '../../services/face_position_validator.dart';

/// O que desenhar sobre o preview.
class OverlayOptions {
  const OverlayOptions({
    this.showOval = true,
    this.showBox = false,
    this.showContours = false,
    this.showLandmarks = false,
  });
  final bool showOval;
  final bool showBox;
  final bool showContours;
  final bool showLandmarks;

  OverlayOptions copyWith({
    bool? showOval,
    bool? showBox,
    bool? showContours,
    bool? showLandmarks,
  }) => OverlayOptions(
    showOval: showOval ?? this.showOval,
    showBox: showBox ?? this.showBox,
    showContours: showContours ?? this.showContours,
    showLandmarks: showLandmarks ?? this.showLandmarks,
  );
}

/// Cores da moldura: cinza (sem rosto), amarelo (ajustando), verde (ok).
Color ovalColorFor(ValidationResult? v) {
  if (v == null || v.status == PositionStatus.noFace) {
    return Colors.grey.shade400;
  }
  return v.isOk ? Colors.greenAccent.shade400 : Colors.amber;
}

/// Desenha a moldura e as marcações da detecção.
///
/// Recebe coordenadas no espaço da imagem em pé ([FrameAnalysis.imageSize]),
/// já espelhadas para a câmera frontal, e as escala para o tamanho do
/// widget — que deve ter a mesma proporção do preview.
class FaceOverlayPainter extends CustomPainter {
  FaceOverlayPainter({
    required this.analysis,
    required this.thresholds,
    required this.options,
    required this.ovalColor,
    this.fallbackImageSize,
  });

  final FrameAnalysis? analysis;
  final DetectionThresholds thresholds;
  final OverlayOptions options;
  final Color ovalColor;

  /// Usado para posicionar a moldura antes do primeiro quadro analisado.
  final Size? fallbackImageSize;

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = analysis?.imageSize ?? fallbackImageSize ?? size;
    final sx = size.width / imageSize.width;
    final sy = size.height / imageSize.height;
    Rect scaleRect(Rect r) =>
        Rect.fromLTRB(r.left * sx, r.top * sy, r.right * sx, r.bottom * sy);
    Offset scalePt(Offset p) => Offset(p.dx * sx, p.dy * sy);

    if (options.showOval) {
      final oval = scaleRect(
        FacePositionValidator.ovalFor(imageSize, thresholds),
      );
      final shade = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addOval(oval);
      canvas.drawPath(shade, Paint()..color = Colors.black.withAlpha(110));
      canvas.drawOval(
        oval,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = ovalColor,
      );
    }

    final faces = analysis?.faces ?? const <FaceObservation>[];
    for (final face in faces) {
      if (options.showBox) {
        canvas.drawRect(
          scaleRect(face.box),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.lightBlueAccent,
        );
      }
      if (options.showContours) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.cyanAccent;
        for (final c in face.contours) {
          final path = Path()..addPolygon(c.map(scalePt).toList(), false);
          canvas.drawPath(path, paint);
        }
      }
      if (options.showLandmarks) {
        final paint = Paint()..color = Colors.pinkAccent;
        for (final p in face.landmarks) {
          canvas.drawCircle(scalePt(p), 4, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(FaceOverlayPainter old) =>
      old.analysis != analysis ||
      old.thresholds != thresholds ||
      old.options != options ||
      old.ovalColor != ovalColor;
}
