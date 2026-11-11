import 'dart:io';

import 'package:flutter/material.dart';

import '../services/capture_storage_service.dart';
import '../services/face_capture_controller.dart';
import '../services/face_position_validator.dart';
import 'widgets/live_camera_view.dart';

String poseLabel(PoseTarget t) {
  switch (t) {
    case PoseTarget.frontal:
      return 'Frontal';
    case PoseTarget.right:
      return 'Direita';
    case PoseTarget.left:
      return 'Esquerda';
    case PoseTarget.up:
      return 'Cima';
    case PoseTarget.down:
      return 'Baixo';
  }
}

String poseInstruction(PoseTarget t) {
  switch (t) {
    case PoseTarget.frontal:
      return 'Olhe diretamente para a câmera.';
    case PoseTarget.right:
      return 'Vire lentamente a cabeça para a direita.';
    case PoseTarget.left:
      return 'Vire lentamente a cabeça para a esquerda.';
    case PoseTarget.up:
      return 'Levante levemente o queixo.';
    case PoseTarget.down:
      return 'Abaixe levemente o queixo.';
  }
}

/// Captura automática em sequência: frontal, direita, esquerda e,
/// opcionalmente (modo avançado), cima e baixo.
class MultiAngleCapturePage extends StatefulWidget {
  const MultiAngleCapturePage({super.key});

  @override
  State<MultiAngleCapturePage> createState() => _MultiAngleCapturePageState();
}

class _MultiAngleCapturePageState extends State<MultiAngleCapturePage> {
  bool _advanced = false;
  bool _started = false;

  List<PoseTarget> get _steps => [
    PoseTarget.frontal,
    PoseTarget.right,
    PoseTarget.left,
    if (_advanced) ...[PoseTarget.up, PoseTarget.down],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _started ? Colors.black : null,
      appBar: AppBar(title: const Text('Múltiplos ângulos')),
      body: _started
          ? LiveCameraView(
              builder: (context, session) =>
                  _SequenceBody(session: session, steps: _steps),
            )
          : _SetupPanel(
              advanced: _advanced,
              steps: _steps,
              onAdvanced: (v) => setState(() => _advanced = v),
              onStart: () => setState(() => _started = true),
            ),
    );
  }
}

class _SetupPanel extends StatelessWidget {
  const _SetupPanel({
    required this.advanced,
    required this.steps,
    required this.onAdvanced,
    required this.onStart,
  });
  final bool advanced;
  final List<PoseTarget> steps;
  final ValueChanged<bool> onAdvanced;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'As fotos serão capturadas automaticamente, sem tocar na tela. '
          'Siga as instruções e mantenha cada posição até a captura.',
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          value: advanced,
          onChanged: onAdvanced,
          title: const Text('Modo avançado'),
          subtitle: const Text('Inclui fotos olhando para cima e para baixo'),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < steps.length; i++)
          ListTile(
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(poseLabel(steps[i])),
            subtitle: Text(poseInstruction(steps[i])),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Iniciar sequência'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
      ],
    );
  }
}

class _SequenceBody extends StatefulWidget {
  const _SequenceBody({required this.session, required this.steps});
  final LiveFaceSession session;
  final List<PoseTarget> steps;

  @override
  State<_SequenceBody> createState() => _SequenceBodyState();
}

class _SequenceBodyState extends State<_SequenceBody> {
  static const _storage = CaptureStorageService();
  late final FaceCaptureController _controller;
  bool _galleryOpen = false;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _controller = FaceCaptureController(
      steps: widget.steps,
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
      // O alvo pode ter mudado após uma captura.
      if (s.analyzer.target != _controller.currentTarget) {
        s.analyzer.target = _controller.currentTarget;
        s.analyzer.stability.reset();
      }
    };
    _controller.addListener(_onChanged);
    _controller.start();
  }

  void _onChanged() {
    if (_controller.state == CaptureState.completed && !_galleryOpen) {
      _openGallery();
    }
  }

  Future<void> _openGallery() async {
    _galleryOpen = true;
    final action = await Navigator.of(context).push<GalleryAction>(
      MaterialPageRoute(
        builder: (_) => CaptureGalleryPage(
          photos: _controller.photos.whereType<CapturedPhoto>().toList(),
        ),
      ),
    );
    _galleryOpen = false;
    if (!mounted) return;
    switch (action) {
      case RetakeAction(:final index):
        final p = _controller.photos[index];
        if (p != null) File(p.path).delete().ignore();
        _controller.retake(index);
        widget.session.analyzer.target = _controller.currentTarget;
      case RestartAction():
        for (final p in _controller.photos.whereType<CapturedPhoto>()) {
          File(p.path).delete().ignore();
        }
        _controller.restart();
        widget.session.analyzer.target = _controller.currentTarget;
      case DoneAction():
      case null:
        Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    widget.session.analyzer.onResult = null;
    _controller.removeListener(_onChanged);
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
              builder: (context, _) => _StepBanner(controller: _controller),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepBanner extends StatelessWidget {
  const _StepBanner({required this.controller});
  final FaceCaptureController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final busy =
        c.state == CaptureState.capturing || c.state == CaptureState.processing;
    final done = c.photos.where((p) => p != null).length;
    return Material(
      color: Colors.black.withAlpha(180),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Passo ${c.stepIndex + 1} de ${c.steps.length} — '
              '${poseLabel(c.currentTarget)}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < c.steps.length; i++)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.photos[i] != null
                          ? Colors.greenAccent.shade400
                          : (i == c.stepIndex ? Colors.amber : Colors.white24),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: busy ? null : c.holdProgress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: Colors.greenAccent.shade400,
              backgroundColor: Colors.white24,
            ),
            const SizedBox(height: 6),
            Text(
              'Estado: ${c.state.name} · capturadas $done/${c.steps.length}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            if (c.state == CaptureState.error)
              FilledButton(
                onPressed: c.start,
                child: const Text('Tentar novamente'),
              ),
          ],
        ),
      ),
    );
  }
}

sealed class GalleryAction {
  const GalleryAction();
}

class RetakeAction extends GalleryAction {
  const RetakeAction(this.index);
  final int index;
}

class RestartAction extends GalleryAction {
  const RestartAction();
}

class DoneAction extends GalleryAction {
  const DoneAction();
}

/// Galeria das fotos da sequência, com opção de repetir cada uma.
class CaptureGalleryPage extends StatelessWidget {
  const CaptureGalleryPage({super.key, required this.photos});
  final List<CapturedPhoto> photos;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fotos capturadas')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.62,
                ),
                itemCount: photos.length,
                itemBuilder: (context, i) {
                  final p = photos[i];
                  return Card.outlined(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Image.file(
                            File(p.path),
                            fit: BoxFit.cover,
                            cacheWidth: 400,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                          child: Text(
                            '${poseLabel(p.target)} · '
                            '${p.captureTime.inMilliseconds} ms',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              Navigator.of(context).pop(RetakeAction(i)),
                          icon: const Icon(Icons.replay, size: 18),
                          label: const Text('Repetir'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(const RestartAction()),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reiniciar tudo'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(const DoneAction()),
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
