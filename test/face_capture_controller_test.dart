import 'dart:async';

import 'package:face_capture_lab/diagnostics/detection_thresholds.dart';
import 'package:face_capture_lab/services/face_capture_controller.dart';
import 'package:face_capture_lab/services/face_position_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'synthetic_frames.dart';

/// Modo de teste com dados sintéticos: exercita o controlador sem câmera.
/// As "fotos" são caminhos fictícios; nenhuma medição biométrica é simulada.
class _FakeCamera {
  int shots = 0;
  int concurrent = 0;
  int maxConcurrent = 0;
  Completer<void>? gate;
  bool fail = false;

  Future<String> take() async {
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    try {
      if (gate != null) await gate!.future;
      if (fail) throw Exception('falha sintética');
      shots++;
      return '/tmp/shot_$shots.jpg';
    } finally {
      concurrent--;
    }
  }

  Future<CapturedPhoto> persist(String p, PoseTarget t, Duration d) async =>
      CapturedPhoto(
        target: t,
        path: p,
        captureTime: d,
        saveTime: Duration.zero,
      );
}

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  const validator = FacePositionValidator();
  const t = DetectionThresholds(); // holdDurationMs = 700
  late _FakeCamera cam;
  late FaceCaptureController c;

  ValidationResult okFrame() => validator.validate(frame([centeredFace()]), t);
  ValidationResult noFace() => validator.validate(frame([]), t);
  ValidationResult farFace() =>
      validator.validate(frame([centeredFace(widthRatio: 0.2)]), t);

  FaceCaptureController make(List<PoseTarget> steps) => FaceCaptureController(
    steps: steps,
    takePhoto: cam.take,
    persistPhoto: cam.persist,
    thresholds: ThresholdsStore(t),
  );

  setUp(() {
    cam = _FakeCamera();
    c = make(const [PoseTarget.frontal]);
  });

  tearDown(() => c.dispose());

  test('estado inicial é idle; start => searchingFace', () {
    expect(c.state, CaptureState.idle);
    c.markInitializing();
    expect(c.state, CaptureState.initializing);
    c.start();
    expect(c.state, CaptureState.searchingFace);
    expect(c.message, 'Posicione seu rosto dentro da moldura.');
  });

  test('ignora quadros antes de start', () {
    c.onFrame(okFrame(), stable: true, timestamp: ms(0));
    expect(c.state, CaptureState.idle);
  });

  test('sem rosto => searchingFace; rosto mal posicionado => adjusting', () {
    c.start();
    c.onFrame(noFace(), stable: false, timestamp: ms(0));
    expect(c.state, CaptureState.searchingFace);
    c.onFrame(farFace(), stable: true, timestamp: ms(100));
    expect(c.state, CaptureState.adjustingPosition);
    expect(c.message, 'Aproxime um pouco o celular.');
  });

  test('ok mas instável não acumula tempo de espera', () {
    c.start();
    for (var i = 0; i < 20; i++) {
      c.onFrame(okFrame(), stable: false, timestamp: ms(i * 100));
    }
    expect(c.state, CaptureState.holdingPosition);
    expect(c.holdProgress, 0);
    expect(cam.shots, 0);
  });

  test('não captura antes de 700 ms contínuos', () {
    c.start();
    c.onFrame(okFrame(), stable: true, timestamp: ms(0));
    c.onFrame(okFrame(), stable: true, timestamp: ms(699));
    expect(c.state, CaptureState.holdingPosition);
    expect(c.holdProgress, closeTo(699 / 700, 1e-9));
    expect(cam.shots, 0);
  });

  test('perder a posição reinicia o tempo de espera', () {
    c.start();
    c.onFrame(okFrame(), stable: true, timestamp: ms(0));
    c.onFrame(okFrame(), stable: true, timestamp: ms(500));
    c.onFrame(farFace(), stable: true, timestamp: ms(600));
    c.onFrame(okFrame(), stable: true, timestamp: ms(700));
    c.onFrame(okFrame(), stable: true, timestamp: ms(1300));
    expect(cam.shots, 0);
    expect(c.state, CaptureState.holdingPosition);
  });

  test('700 ms estável => capturing → processing → completed', () async {
    final states = <CaptureState>[];
    c.addListener(() => states.add(c.state));
    c.start();
    c.onFrame(okFrame(), stable: true, timestamp: ms(0));
    c.onFrame(okFrame(), stable: true, timestamp: ms(700));
    expect(c.state, CaptureState.capturing);
    await pumpEventQueue();
    expect(c.state, CaptureState.completed);
    expect(
      states,
      containsAllInOrder([
        CaptureState.capturing,
        CaptureState.processing,
        CaptureState.completed,
      ]),
    );
    expect(c.photos.single!.path, '/tmp/shot_1.jpg');
    expect(c.photos.single!.target, PoseTarget.frontal);
  });

  test(
    'nunca há capturas simultâneas; quadros durante captura são ignorados',
    () async {
      cam.gate = Completer<void>();
      c.start();
      c.onFrame(okFrame(), stable: true, timestamp: ms(0));
      c.onFrame(okFrame(), stable: true, timestamp: ms(800));
      for (var i = 1; i <= 10; i++) {
        c.onFrame(okFrame(), stable: true, timestamp: ms(800 + i * 100));
      }
      expect(c.state, CaptureState.capturing);
      cam.gate!.complete();
      await pumpEventQueue();
      expect(cam.maxConcurrent, 1);
      expect(cam.shots, 1);
      expect(c.state, CaptureState.completed);
    },
  );

  test('falha na câmera => error; start recupera', () async {
    cam.fail = true;
    c.start();
    c.onFrame(okFrame(), stable: true, timestamp: ms(0));
    c.onFrame(okFrame(), stable: true, timestamp: ms(700));
    await pumpEventQueue();
    expect(c.state, CaptureState.error);
    expect(c.error, contains('falha sintética'));
    c.start();
    expect(c.state, CaptureState.searchingFace);
  });

  test('restart descarta a foto e recomeça', () async {
    c.start();
    c.onFrame(okFrame(), stable: true, timestamp: ms(0));
    c.onFrame(okFrame(), stable: true, timestamp: ms(700));
    await pumpEventQueue();
    expect(c.state, CaptureState.completed);
    c.restart();
    expect(c.state, CaptureState.searchingFace);
    expect(c.photos.single, isNull);
  });

  test('sequência de passos avança para o próximo alvo', () async {
    c.dispose();
    c = make(const [PoseTarget.frontal, PoseTarget.right]);
    c.start();
    c.onFrame(okFrame(), stable: true, timestamp: ms(0));
    c.onFrame(okFrame(), stable: true, timestamp: ms(700));
    await pumpEventQueue();
    expect(c.state, CaptureState.searchingFace);
    expect(c.currentTarget, PoseTarget.right);
    expect(c.stepIndex, 1);
  });
}
