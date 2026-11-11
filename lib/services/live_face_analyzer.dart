import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/face_observation.dart';
import '../diagnostics/detection_thresholds.dart';
import '../diagnostics/frame_metrics.dart';
import 'camera_service.dart';
import 'face_detection_service.dart';
import 'face_position_validator.dart';
import 'image_rotation.dart';
import 'stability_tracker.dart';

class LiveFaceAnalyzer extends ChangeNotifier {
  LiveFaceAnalyzer({
    required this.camera,
    required this.detector,
    ThresholdsStore? thresholds,
    this.validator = const FacePositionValidator(),
  }) : thresholds = thresholds ?? thresholdsStore;

  final CameraService camera;
  final FaceDetectionService detector;
  final ThresholdsStore thresholds;
  final FacePositionValidator validator;
  final FrameMetrics metrics = FrameMetrics();
  final StabilityTracker stability = StabilityTracker();
  final Stopwatch _clock = Stopwatch()..start();

  PoseTarget target = PoseTarget.frontal;

  FrameAnalysis? _analysis;
  ValidationResult? _validation;
  int _generation = 0;
  bool _running = false;
  bool _disposed = false;

  FrameAnalysis? get analysis => _analysis;
  ValidationResult? get validation => _validation;
  bool get isRunning => _running;

  void Function(FrameAnalysis, ValidationResult)? onResult;

  Future<void> start() async {
    if (_running || _disposed) return;
    _running = true;
    _generation++;
    stability.reset();
    metrics.reset();
    await camera.startImageStream(_onFrame);
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _generation++;
    await camera.stopImageStream();
  }

  void _onFrame(CameraImage image) {
    metrics.onFrameReceived();
    if (!_running || detector.isBusy) {
      metrics.onFrameDropped();
      return;
    }
    _analyze(image, _generation);
  }

  Future<void> _analyze(CameraImage image, int generation) async {
    final controller = camera.controller;
    if (controller == null) return;
    final rotation = frameRotationDegrees(
      isAndroid: Platform.isAndroid,
      isFrontCamera: camera.isFront,
      sensorOrientation: camera.sensorOrientation,
      deviceRotation: deviceOrientationDegrees(
        controller.value.deviceOrientation,
      ),
    );

    FrameAnalysis? result;
    try {
      result = await detector.processCameraImage(
        image,
        rotationDegrees: rotation,
        mirror: camera.isFront,
        timestamp: _clock.elapsed,
      );
    } on PlatformException catch (e) {
      // Não registra conteúdo de imagem; apenas o código do erro.
      debugPrint('Falha na detecção: ${e.code}');
    }
    if (result == null) {
      metrics.onFrameDropped();
      return;
    }
    if (_disposed || generation != _generation) return; // resultado obsoleto

    final t = thresholds.value;
    final v = validator.validate(result, t, target: target);
    stability.update(
      result.faces.length == 1 ? result.faces.single : null,
      result.imageSize,
      result.timestamp,
      t,
    );
    metrics.onFrameAnalyzed(_clock.elapsed, result.processingTime);
    _analysis = result;
    _validation = v;
    onResult?.call(result, v);
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _running = false;
    _generation++;
    super.dispose();
  }
}
