import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/capture_storage_service.dart';
import '../services/face_capture_controller.dart';
import '../services/face_position_validator.dart';
import 'widgets/live_camera_view.dart';

/// Captura facial orientada: frontal automática.
class GuidedCapturePage extends StatelessWidget {
  const GuidedCapturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Captura facial orientada')),
      body: LiveCameraView(
        builder: (context, session) => _GuidedCaptureBody(session: session),
      ),
    );
  }
}

class _GuidedCaptureBody extends StatefulWidget {
  const _GuidedCaptureBody({required this.session});
  final LiveFaceSession session;

  @override
  State<_GuidedCaptureBody> createState() => _GuidedCaptureBodyState();
}

class _GuidedCaptureBodyState extends State<_GuidedCaptureBody> {
  static const _storage = CaptureStorageService();
  late final FaceCaptureController _controller;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _controller = FaceCaptureController(
      steps: const [PoseTarget.frontal],
      takePhoto: () async => (await s.camera.takePicture()).path,
      persistPhoto: _storage.persist,
    );
    s.analyzer.target = _controller.currentTarget;
    s.analyzer.onResult = (frame, v) {
      _controller.onFrame(
        v,
        stable: s.analyzer.stability.isStable,
        timestamp: frame.timestamp,
      );
      s.analyzer.target = _controller.currentTarget;
    };
    _controller.addListener(_onControllerChanged);
    _controller.start();
  }

  void _onControllerChanged() {
    if (_controller.state != CaptureState.completed) return;
    final photo = _controller.photos.first;
    if (photo == null || !mounted) return;
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(builder: (_) => CaptureResultPage(photo: photo)),
        )
        .then((retake) {
          if (!mounted) return;
          if (retake == true) {
            // A foto descartada não deve permanecer no aparelho.
            File(photo.path).delete().ignore();
            _controller.restart();
          } else {
            Navigator.of(context).pop();
          }
        });
  }

  @override
  void dispose() {
    widget.session.analyzer.onResult = null;
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreviewWithOverlay(session: widget.session),
        Positioned(
          left: 16,
          right: 16,
          bottom: 32,
          child: SafeArea(
            top: false,
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) =>
                  _InstructionBanner(controller: _controller),
            ),
          ),
        ),
      ],
    );
  }
}

/// Mensagem de orientação, progresso da espera e estado técnico.
class _InstructionBanner extends StatelessWidget {
  const _InstructionBanner({required this.controller});
  final FaceCaptureController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final busy =
        c.state == CaptureState.capturing || c.state == CaptureState.processing;
    return Material(
      color: Colors.black.withAlpha(180),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                c.message,
                key: ValueKey(c.message),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: busy ? null : c.holdProgress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: Colors.greenAccent.shade400,
              backgroundColor: Colors.white24,
            ),
            const SizedBox(height: 8),
            Text(
              'Estado: ${c.state.name}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            if (c.state == CaptureState.error) ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: c.start,
                child: const Text('Tentar novamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mostra a foto capturada com tempos e dimensões.
/// Retorna `true` ao navegador se o usuário quiser repetir.
class CaptureResultPage extends StatelessWidget {
  const CaptureResultPage({super.key, required this.photo});
  final CapturedPhoto photo;

  Future<Size> _fileImageSize() async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(photo.path);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = Size(
      descriptor.width.toDouble(),
      descriptor.height.toDouble(),
    );
    descriptor.dispose();
    buffer.dispose();
    return size;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Foto capturada')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image(
                    image: FileImage(File(photo.path)),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            FutureBuilder<Size>(
              future: _fileImageSize(),
              builder: (context, snap) {
                final s = snap.data;
                return Text(
                  'Arquivo: ${s == null ? '...' : '${s.width.toInt()}×${s.height.toInt()} px'}\n'
                  'Captura: ${photo.captureTime.inMilliseconds} ms · '
                  'Gravação: ${photo.saveTime.inMilliseconds} ms',
                  textAlign: TextAlign.center,
                );
              },
            ),
            const SizedBox(height: 4),
            const Text(
              'Salva somente no armazenamento privado do aplicativo.',
              style: TextStyle(fontSize: 12),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.replay),
                      label: const Text('Repetir'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.check),
                      label: const Text('Concluir'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
