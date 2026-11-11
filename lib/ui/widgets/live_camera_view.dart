import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../diagnostics/detection_thresholds.dart';
import '../../services/camera_service.dart';
import '../../services/face_detection_service.dart';
import '../../services/live_face_analyzer.dart';
import 'face_overlay_painter.dart';

/// Serviços de uma sessão de câmera ao vivo.
class LiveFaceSession {
  LiveFaceSession(this.camera, this.detector, this.analyzer);
  final CameraService camera;
  final FaceDetectionService detector;
  final LiveFaceAnalyzer analyzer;
}

/// Gerencia câmera + detector + analisador, incluindo:
/// - explicação do uso da câmera antes do pedido de permissão;
/// - pausa ao ir para segundo plano e retomada ao voltar;
/// - descarte correto de câmera e detector.
class LiveCameraView extends StatefulWidget {
  const LiveCameraView({
    super.key,
    required this.builder,
    this.detectorConfig = const DetectorConfig(),
  });

  final DetectorConfig detectorConfig;
  final Widget Function(BuildContext context, LiveFaceSession session) builder;

  @override
  State<LiveCameraView> createState() => _LiveCameraViewState();
}

class _LiveCameraViewState extends State<LiveCameraView>
    with WidgetsBindingObserver {
  /// A explicação é exibida uma vez por execução do aplicativo.
  static bool _consentShown = false;

  LiveFaceSession? _session;
  String? _error;
  bool _permissionDenied = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_consentShown) _start();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    final camera = CameraService();
    final detector = FaceDetectionService(config: widget.detectorConfig);
    try {
      await camera.initialize();
      final analyzer = LiveFaceAnalyzer(camera: camera, detector: detector);
      if (!mounted) {
        analyzer.dispose();
        await camera.dispose();
        await detector.close();
        return;
      }
      await analyzer.start();
      setState(() => _session = LiveFaceSession(camera, detector, analyzer));
    } on CameraServiceException catch (e) {
      await camera.dispose();
      await detector.close();
      if (mounted) {
        setState(() {
          _error = e.message;
          _permissionDenied = e.permissionDenied;
        });
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    final s = _session;
    _session = null;
    if (s == null) return;
    await s.analyzer.stop();
    s.analyzer.dispose();
    await s.camera.dispose();
    await s.detector.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_consentShown) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_session != null) {
        _stop();
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_session == null && !_starting) _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_consentShown) {
      return _ConsentPanel(
        onAccept: () {
          _consentShown = true;
          _start();
        },
      );
    }
    if (_error != null) {
      return _ErrorPanel(
        message: _error!,
        permissionDenied: _permissionDenied,
        onRetry: _start,
      );
    }
    final s = _session;
    if (s == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return widget.builder(context, s);
  }
}

/// Preview da câmera ocupando a área disponível (corte tipo "cover") com o
/// overlay alinhado exatamente sobre a imagem.
class CameraPreviewWithOverlay extends StatelessWidget {
  const CameraPreviewWithOverlay({
    super.key,
    required this.session,
    this.options = const OverlayOptions(),
  });

  final LiveFaceSession session;
  final OverlayOptions options;

  @override
  Widget build(BuildContext context) {
    final controller = session.camera.controller!;
    final preview = controller.value.previewSize; // em paisagem (w > h)
    // App travado em retrato: a área do preview é a transposta.
    final portrait = preview == null
        ? const Size(720, 1280)
        : Size(preview.height, preview.width);

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: portrait.width,
          height: portrait.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(controller),
              // Só o overlay é reconstruído a cada quadro analisado.
              RepaintBoundary(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    session.analyzer,
                    thresholdsStore,
                  ]),
                  builder: (context, _) {
                    final v = session.analyzer.validation;
                    return TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: ovalColorFor(v)),
                      duration: const Duration(milliseconds: 250),
                      builder: (context, color, _) => CustomPaint(
                        painter: FaceOverlayPainter(
                          analysis: session.analyzer.analysis,
                          thresholds: thresholdsStore.value,
                          options: options,
                          ovalColor: color ?? Colors.grey,
                          fallbackImageSize: portrait,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsentPanel extends StatelessWidget {
  const _ConsentPanel({required this.onAccept});
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.photo_camera_front_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Uso da câmera',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Este laboratório usa a câmera frontal para detectar a posição '
              'do seu rosto e capturar fotografias de teste.\n\n'
              'Todo o processamento acontece neste aparelho. Nenhuma imagem '
              'ou informação biométrica é enviada a servidores, e os dados '
              'são utilizados exclusivamente nos testes. Você pode apagar as '
              'capturas a qualquer momento.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onAccept,
              icon: const Icon(Icons.check),
              label: const Text('Entendi, permitir câmera'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.permissionDenied,
    required this.onRetry,
  });
  final String message;
  final bool permissionDenied;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              permissionDenied ? Icons.no_photography_outlined : Icons.error,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
