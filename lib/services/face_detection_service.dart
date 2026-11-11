import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    as mlkit;

import '../core/face_observation.dart';

class DetectorConfig {
  const DetectorConfig({
    this.enableContours = false,
    this.enableLandmarks = true,
    this.accurate = false,
    this.minFaceSize = 0.15,
  });

  final bool enableContours;
  final bool enableLandmarks;
  final bool accurate;
  final double minFaceSize;

  DetectorConfig copyWith({
    bool? enableContours,
    bool? enableLandmarks,
    bool? accurate,
    double? minFaceSize,
  }) => DetectorConfig(
    enableContours: enableContours ?? this.enableContours,
    enableLandmarks: enableLandmarks ?? this.enableLandmarks,
    accurate: accurate ?? this.accurate,
    minFaceSize: minFaceSize ?? this.minFaceSize,
  );
}

class FaceDetectionService {
  FaceDetectionService({DetectorConfig config = const DetectorConfig()})
    : _config = config,
      _detector = _create(config);

  DetectorConfig _config;
  mlkit.FaceDetector _detector;
  bool _busy = false;
  bool _closed = false;

  DetectorConfig get config => _config;
  bool get isBusy => _busy;

  static mlkit.FaceDetector _create(DetectorConfig c) => mlkit.FaceDetector(
    options: mlkit.FaceDetectorOptions(
      enableContours: c.enableContours,
      enableLandmarks: c.enableLandmarks,
      enableClassification: false,
      enableTracking: false,
      minFaceSize: c.minFaceSize,
      performanceMode: c.accurate
          ? mlkit.FaceDetectorMode.accurate
          : mlkit.FaceDetectorMode.fast,
    ),
  );

  Future<void> updateConfig(DetectorConfig next) async {
    if (_closed) return;
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final old = _detector;
    _config = next;
    _detector = _create(next);
    await old.close();
  }

  Future<FrameAnalysis?> processCameraImage(
    CameraImage image, {
    required int rotationDegrees,
    required bool mirror,
    required Duration timestamp,
  }) async {
    if (_busy || _closed) return null;
    final input = _toInputImage(image, rotationDegrees);
    if (input == null) return null;

    _busy = true;
    final sw = Stopwatch()..start();
    try {
      final faces = await _detector.processImage(input);
      sw.stop();

      final sensorSize = Size(image.width.toDouble(), image.height.toDouble());
      final upright = (rotationDegrees == 90 || rotationDegrees == 270)
          ? Size(sensorSize.height, sensorSize.width)
          : sensorSize;

      return FrameAnalysis(
        faces: [for (final f in faces) toObservation(f, upright.width, mirror)],
        imageSize: upright,
        processingTime: sw.elapsed,
        timestamp: timestamp,
        meanLuma: sampleMeanLuma(image),
        rotationDegrees: rotationDegrees,
        sensorSize: sensorSize,
      );
    } finally {
      _busy = false;
    }
  }

  Future<List<FaceObservation>> processFile(String path) async {
    final faces = await _detector.processImage(
      mlkit.InputImage.fromFilePath(path),
    );
    return [for (final f in faces) toObservation(f, 0, false)];
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await _detector.close();
  }

  mlkit.InputImage? _toInputImage(CameraImage image, int rotationDegrees) {
    final rotation = mlkit.InputImageRotationValue.fromRawValue(
      rotationDegrees,
    );
    if (rotation == null) return null;

    final format = mlkit.InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != mlkit.InputImageFormat.nv21) ||
        (Platform.isIOS && format != mlkit.InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return mlkit.InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: mlkit.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  static FaceObservation toObservation(
    mlkit.Face f,
    double width,
    bool mirror,
  ) {
    Offset p(math.Point<int> pt) =>
        Offset(mirror ? width - pt.x : pt.x.toDouble(), pt.y.toDouble());
    final b = f.boundingBox;
    final box = mirror
        ? Rect.fromLTRB(width - b.right, b.top, width - b.left, b.bottom)
        : b;
    return FaceObservation(
      box: box,
      eulerX: f.headEulerAngleX,
      eulerY: f.headEulerAngleY,
      eulerZ: f.headEulerAngleZ,
      trackingId: f.trackingId,
      landmarks: [
        for (final l in f.landmarks.values)
          if (l != null) p(l.position),
      ],
      contours: [
        for (final c in f.contours.values)
          if (c != null && c.points.isNotEmpty)
            [for (final pt in c.points) p(pt)],
      ],
    );
  }

  static double? sampleMeanLuma(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final Uint8List bytes = plane.bytes;
    final stride = plane.bytesPerRow;
    const step = 16;
    var sum = 0.0;
    var n = 0;
    final isBgra = image.format.group == ImageFormatGroup.bgra8888;
    for (var y = 0; y < image.height; y += step) {
      final row = y * stride;
      for (var x = 0; x < image.width; x += step) {
        if (isBgra) {
          final i = row + x * 4;
          if (i + 2 >= bytes.length) break;
          sum += 0.114 * bytes[i] + 0.587 * bytes[i + 1] + 0.299 * bytes[i + 2];
        } else {
          final i = row + x;
          if (i >= bytes.length) break;
          sum += bytes[i];
        }
        n++;
      }
    }
    return n == 0 ? null : sum / n;
  }
}
