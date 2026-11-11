import 'package:face_capture_lab/diagnostics/detection_thresholds.dart';
import 'package:face_capture_lab/diagnostics/frame_metrics.dart';
import 'package:face_capture_lab/services/image_rotation.dart';
import 'package:face_capture_lab/services/stability_tracker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'synthetic_frames.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  const t = DetectionThresholds();

  group('StabilityTracker', () {
    test('primeiro quadro nunca é estável', () {
      final s = StabilityTracker()
        ..update(centeredFace(), kFrameSize, ms(0), t);
      expect(s.isStable, isFalse);
    });

    test('rosto parado acumula tempo estável', () {
      final s = StabilityTracker();
      for (var i = 0; i <= 10; i++) {
        s.update(centeredFace(dx: 0.001 * i), kFrameSize, ms(i * 100), t);
      }
      expect(s.isStable, isTrue);
      expect(s.stableFor, ms(900));
    });

    test('movimento grande reinicia a estabilidade', () {
      final s = StabilityTracker()
        ..update(centeredFace(), kFrameSize, ms(0), t)
        ..update(centeredFace(), kFrameSize, ms(100), t)
        ..update(centeredFace(), kFrameSize, ms(200), t);
      expect(s.isStable, isTrue);
      s.update(centeredFace(dx: 0.1), kFrameSize, ms(300), t);
      expect(s.isStable, isFalse);
      expect(s.stableFor, Duration.zero);
    });

    test('variação de ângulo acima do limite reinicia', () {
      final s = StabilityTracker()
        ..update(centeredFace(y: 0), kFrameSize, ms(0), t)
        ..update(centeredFace(y: 1), kFrameSize, ms(100), t);
      expect(s.isStable, isTrue);
      s.update(centeredFace(y: 8), kFrameSize, ms(200), t);
      expect(s.isStable, isFalse);
    });

    test('perder o rosto reinicia', () {
      final s = StabilityTracker()
        ..update(centeredFace(), kFrameSize, ms(0), t)
        ..update(centeredFace(), kFrameSize, ms(100), t)
        ..update(null, kFrameSize, ms(200), t);
      expect(s.isStable, isFalse);
    });
  });

  group('rotação do quadro', () {
    test('Android, frontal, sensor 270, retrato => 270', () {
      expect(
        frameRotationDegrees(
          isAndroid: true,
          isFrontCamera: true,
          sensorOrientation: 270,
          deviceRotation: 0,
        ),
        270,
      );
    });

    test('Android, traseira, sensor 90, paisagem esquerda => 0', () {
      expect(
        frameRotationDegrees(
          isAndroid: true,
          isFrontCamera: false,
          sensorOrientation: 90,
          deviceRotation: 90,
        ),
        0,
      );
    });

    test('iOS usa a orientação do sensor', () {
      expect(
        frameRotationDegrees(
          isAndroid: false,
          isFrontCamera: true,
          sensorOrientation: 90,
          deviceRotation: 0,
        ),
        90,
      );
    });

    test('graus da orientação do aparelho', () {
      expect(deviceOrientationDegrees(DeviceOrientation.portraitUp), 0);
      expect(deviceOrientationDegrees(DeviceOrientation.landscapeRight), 270);
    });
  });

  group('FrameMetrics', () {
    test('FPS calculado pela janela de quadros analisados', () {
      final m = FrameMetrics();
      for (var i = 0; i < 11; i++) {
        m.onFrameAnalyzed(ms(i * 100), ms(30));
      }
      expect(m.analysisFps, closeTo(10, 1e-6));
      expect(m.averageProcessingMs, closeTo(30, 1e-6));
    });
  });
}
