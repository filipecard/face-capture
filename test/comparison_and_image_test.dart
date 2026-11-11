import 'dart:math' as math;
import 'dart:ui';

import 'package:face_capture_lab/services/face_comparison_service.dart';
import 'package:face_capture_lab/services/image_processing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('similaridade cosseno', () {
    final cos = FaceComparisonService.cosineSimilarity;

    test('vetores iguais => 1', () {
      expect(cos([1, 2, 3], [1, 2, 3]), closeTo(1, 1e-12));
    });

    test('vetores opostos => -1', () {
      expect(cos([1, -2, 3], [-1, 2, -3]), closeTo(-1, 1e-12));
    });

    test('vetores ortogonais => 0', () {
      expect(cos([1, 0], [0, 5]), closeTo(0, 1e-12));
    });

    test('invariante à escala', () {
      expect(cos([1, 2, 3], [10, 20, 30]), closeTo(1, 1e-12));
    });

    test('valor conhecido: 45°', () {
      expect(cos([1, 0], [1, 1]), closeTo(math.sqrt1_2, 1e-12));
    });

    test('dimensões diferentes, vazio ou norma zero => erro', () {
      expect(() => cos([1, 2], [1]), throwsArgumentError);
      expect(() => cos([], []), throwsArgumentError);
      expect(() => cos([0, 0], [1, 1]), throwsArgumentError);
    });
  });

  group('processamento de imagem', () {
    test('pixelRect converte e limita à imagem', () {
      final r = ImageProcessingService.pixelRect(
        const Rect.fromLTRB(-0.1, 0.25, 0.5, 1.2),
        200,
        100,
      );
      expect(r, const Rect.fromLTRB(0, 25, 100, 100));
    });

    test('pixelRect garante ao menos 1 px', () {
      final r = ImageProcessingService.pixelRect(
        const Rect.fromLTRB(0.5, 0.5, 0.5, 0.5),
        100,
        100,
      );
      expect(r.width, 1);
      expect(r.height, 1);
    });

    test('prepare aplica orientação EXIF (90°) e reduz tamanho', () {
      // Imagem 400×200 marcada com EXIF orientation = 6 (girar 90°).
      final src = img.Image(width: 400, height: 200);
      src.exif.imageIfd['Orientation'] = 6;
      final jpg = img.encodeJpg(src);
      final p = ImageProcessingService.prepareSync(jpg, maxSide: 300);
      expect(p.height, greaterThan(p.width)); // ficou em pé
      expect(p.height, 300);
      expect(p.width, 150);
    });

    test('crop recorta a região normalizada', () {
      final jpg = img.encodeJpg(img.Image(width: 400, height: 300));
      final c = ImageProcessingService.cropSync(
        jpg,
        const Rect.fromLTWH(0.25, 0.5, 0.5, 0.5),
      );
      expect(c.width, 200);
      expect(c.height, 150);
    });

    test('bytes inválidos => FormatException', () {
      expect(
        () => ImageProcessingService.prepareSync(
          img.encodeJpg(img.Image(width: 1, height: 1)).sublist(0, 10),
        ),
        throwsFormatException,
      );
    });
  });
}
