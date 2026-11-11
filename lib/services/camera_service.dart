import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraServiceException implements Exception {
  CameraServiceException(this.message, {this.permissionDenied = false});
  final String message;
  final bool permissionDenied;
  @override
  String toString() => message;
}

class CameraService {
  CameraController? _controller;
  bool _streaming = false;
  bool _capturing = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isStreaming => _streaming;

  CameraDescription? get description => _controller?.description;
  bool get isFront => description?.lensDirection == CameraLensDirection.front;
  int get sensorOrientation => description?.sensorOrientation ?? 0;

  Future<void> initialize({
    ResolutionPreset preset = ResolutionPreset.high,
  }) async {
    await dispose();
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (e) {
      throw _translate(e);
    }
    if (cameras.isEmpty) {
      throw CameraServiceException('Nenhuma câmera encontrada no aparelho.');
    }
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      camera,
      preset,
      enableAudio: false,

      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      throw _translate(e);
    }
    _controller = controller;
  }

  Future<void> startImageStream(void Function(CameraImage) onFrame) async {
    final c = _controller;
    if (c == null || _streaming) return;
    await c.startImageStream(onFrame);
    _streaming = true;
  }

  Future<void> stopImageStream() async {
    final c = _controller;
    if (c == null || !_streaming) return;
    _streaming = false;
    try {
      await c.stopImageStream();
    } on CameraException catch (e) {
      debugPrint('stopImageStream: ${e.code}');
    }
  }

  Future<XFile> takePicture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      throw CameraServiceException('Câmera não inicializada.');
    }
    if (_capturing || c.value.isTakingPicture) {
      throw CameraServiceException('Já existe uma captura em andamento.');
    }
    _capturing = true;
    try {
      return await c.takePicture();
    } on CameraException catch (e) {
      throw _translate(e);
    } finally {
      _capturing = false;
    }
  }

  Future<void> dispose() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    if (_streaming) {
      _streaming = false;
      try {
        await c.stopImageStream();
      } catch (_) {}
    }
    await c.dispose();
  }

  CameraServiceException _translate(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return CameraServiceException(
          'Permissão de câmera negada. Libere o acesso nas configurações do '
          'aparelho para usar o laboratório.',
          permissionDenied: true,
        );
      default:
        return CameraServiceException(
          'Falha na câmera (${e.code}): ${e.description ?? ''}',
        );
    }
  }
}
