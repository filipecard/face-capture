import 'dart:ui';

import 'package:face_capture_lab/core/face_observation.dart';
import 'package:face_capture_lab/diagnostics/detection_thresholds.dart';
import 'package:face_capture_lab/services/face_position_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'synthetic_frames.dart';

void main() {
  const t = DetectionThresholds();
  const v = FacePositionValidator();

  group('ausência e multiplicidade de rostos', () {
    test('sem rosto => noFace com mensagem de moldura', () {
      final r = v.validate(frame([]), t);
      expect(r.status, PositionStatus.noFace);
      expect(r.issues, [PositionIssue.noFace]);
      expect(r.message, 'Posicione seu rosto dentro da moldura.');
    });

    test('dois rostos => multipleFaces', () {
      final r = v.validate(frame([centeredFace(), centeredFace()]), t);
      expect(r.status, PositionStatus.adjusting);
      expect(r.issues, [PositionIssue.multipleFaces]);
      expect(r.face, isNull);
    });
  });

  group('rosto ideal', () {
    test('centralizado, tamanho e ângulos ok => ok', () {
      final r = v.validate(frame([centeredFace()]), t);
      expect(r.issues, isEmpty);
      expect(r.isOk, isTrue);
      expect(r.isCentered, isTrue);
      expect(r.message, 'Mantenha essa posição.');
    });
  });

  group('proporção do rosto', () {
    test('cálculo: largura do rosto ÷ largura do quadro', () {
      expect(
        FacePositionValidator.faceWidthRatio(
          const Rect.fromLTWH(0, 0, 360, 400),
          kFrameSize,
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('rosto pequeno => aproximar', () {
      final r = v.validate(frame([centeredFace(widthRatio: 0.2)]), t);
      expect(r.issues.first, PositionIssue.tooFar);
      expect(r.message, 'Aproxime um pouco o celular.');
    });

    test('rosto grande => afastar', () {
      final r = v.validate(frame([centeredFace(widthRatio: 0.85)]), t);
      expect(r.issues, contains(PositionIssue.tooClose));
      expect(r.message, 'Afaste um pouco o celular.');
    });
  });

  group('centralização (coordenadas já espelhadas para a tela)', () {
    test('rosto à direita na tela => mover para a esquerda', () {
      final r = v.validate(frame([centeredFace(dx: 0.2)]), t);
      expect(r.issues, [PositionIssue.moveLeft]);
      expect(r.message, 'Mova o rosto para a esquerda.');
      expect(r.isCentered, isFalse);
    });

    test('rosto à esquerda na tela => mover para a direita', () {
      final r = v.validate(frame([centeredFace(dx: -0.2)]), t);
      expect(r.issues, [PositionIssue.moveRight]);
    });

    test('deslocamento dentro da tolerância => centralizado', () {
      final r = v.validate(frame([centeredFace(dx: 0.05, dy: -0.05)]), t);
      expect(r.isCentered, isTrue);
    });

    test('deslocamento vertical => voltar para a moldura', () {
      final r = v.validate(frame([centeredFace(dy: 0.25)]), t);
      expect(r.issues, [PositionIssue.moveUp]);
      expect(r.message, 'Posicione seu rosto dentro da moldura.');
    });

    test('centerOffset é medido em relação ao centro da moldura', () {
      final off = FacePositionValidator.centerOffset(
        Rect.fromCenter(
          center: Offset(kFrameSize.width * 0.5, kFrameSize.height * 0.45),
          width: 100,
          height: 100,
        ),
        kFrameSize,
        t,
      );
      expect(off.dx, closeTo(0, 1e-9));
      expect(off.dy, closeTo(0, 1e-9));
    });
  });

  group('ângulos frontais', () {
    test('Z acima do limite => cabeça reta', () {
      final r = v.validate(frame([centeredFace(z: 15)]), t);
      expect(r.issues, [PositionIssue.headTilted]);
      expect(r.message, 'Mantenha a cabeça reta.');
    });

    test('Y acima do limite => olhar para a câmera', () {
      final r = v.validate(frame([centeredFace(y: -12)]), t);
      expect(r.issues, [PositionIssue.notLookingAtCamera]);
      expect(r.message, 'Olhe diretamente para a câmera.');
    });

    test('X acima do limite => olhar para a câmera', () {
      final r = v.validate(frame([centeredFace(x: 11)]), t);
      expect(r.issues, [PositionIssue.notLookingAtCamera]);
    });

    test('limite é inclusivo (exatamente 10° é aceito)', () {
      final r = v.validate(frame([centeredFace(x: 10, y: -10, z: 10)]), t);
      expect(r.isOk, isTrue);
    });

    test('ângulos ausentes => problema explícito', () {
      final r = v.validate(
        frame([FaceObservation(box: centeredFace().box)]),
        t,
      );
      expect(r.issues, [PositionIssue.missingAngles]);
    });
  });

  group('ângulos laterais com sinal calibrável', () {
    // Padrão: virar à direita do usuário => Y negativo.
    test('direita: Y = -20 está na faixa 15–30', () {
      final r = v.validate(
        frame([centeredFace(y: -20)]),
        t,
        target: PoseTarget.right,
      );
      expect(r.isOk, isTrue);
    });

    test('direita: Y = +20 (lado errado) => vire para a direita', () {
      final r = v.validate(
        frame([centeredFace(y: 20)]),
        t,
        target: PoseTarget.right,
      );
      expect(r.issues, [PositionIssue.turnRight]);
    });

    test('esquerda: Y = +20 está na faixa', () {
      final r = v.validate(
        frame([centeredFace(y: 20)]),
        t,
        target: PoseTarget.left,
      );
      expect(r.isOk, isTrue);
    });

    test('lateral além do máximo => voltar um pouco', () {
      final r = v.validate(
        frame([centeredFace(y: 40)]),
        t,
        target: PoseTarget.left,
      );
      expect(r.issues, [PositionIssue.turnedTooFar]);
    });

    test('sinal invertido pela calibração troca o lado', () {
      final inv = t.copyWith(yawSignForUserRight: 1);
      final r = v.validate(
        frame([centeredFace(y: 20)]),
        inv,
        target: PoseTarget.right,
      );
      expect(r.isOk, isTrue);
    });

    test('cima: X = 15 na faixa 10–25', () {
      final r = v.validate(
        frame([centeredFace(x: 15)]),
        t,
        target: PoseTarget.up,
      );
      expect(r.isOk, isTrue);
    });

    test('baixo: X = 5 insuficiente => abaixar o queixo', () {
      final r = v.validate(
        frame([centeredFace(x: -5)]),
        t,
        target: PoseTarget.down,
      );
      expect(r.issues, [PositionIssue.lookDown]);
    });
  });

  group('iluminação', () {
    test('quadro escuro => tooDark', () {
      final r = v.validate(frame([centeredFace()], luma: 20), t);
      expect(r.issues.first, PositionIssue.tooDark);
    });

    test('quadro estourado => tooBright', () {
      final r = v.validate(frame([centeredFace()], luma: 240), t);
      expect(r.issues.first, PositionIssue.tooBright);
    });
  });
}
