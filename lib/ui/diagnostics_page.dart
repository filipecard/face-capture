import 'package:flutter/material.dart';

import '../diagnostics/detection_thresholds.dart';
import 'widgets/face_overlay_painter.dart';
import 'widgets/live_camera_view.dart';

/// Painel técnico: câmera ao vivo, métricas da detecção e ajuste de limites.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  OverlayOptions _overlay = const OverlayOptions(
    showOval: true,
    showBox: true,
    showLandmarks: true,
  );
  bool _showInfo = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Diagnóstico')),
      body: LiveCameraView(
        builder: (context, session) => Stack(
          fit: StackFit.expand,
          children: [
            CameraPreviewWithOverlay(session: session, options: _overlay),
            if (_showInfo)
              Positioned(
                left: 8,
                top: 8,
                right: 8,
                child: _MetricsPanel(session: session),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Toolbar(
                overlay: _overlay,
                showInfo: _showInfo,
                session: session,
                onOverlay: (o) => setState(() => _overlay = o),
                onShowInfo: (v) => setState(() => _showInfo = v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.session});
  final LiveFaceSession session;

  @override
  Widget build(BuildContext context) {
    final analyzer = session.analyzer;
    return ListenableBuilder(
      listenable: analyzer,
      builder: (context, _) {
        final a = analyzer.analysis;
        final v = analyzer.validation;
        final m = analyzer.metrics;
        final face =
            v?.face ?? (a?.faces.isNotEmpty == true ? a!.faces.first : null);
        final preview = session.camera.controller?.value.previewSize;
        String f(double? x, [int d = 1]) =>
            x == null ? '—' : x.toStringAsFixed(d);

        final lines = <String>[
          'Rostos: ${a?.faces.length ?? 0}',
          'Euler X: ${f(face?.eulerX)}°   Y: ${f(face?.eulerY)}°   Z: ${f(face?.eulerZ)}°',
          if (face != null)
            'Caixa: L${f(face.box.left, 0)} T${f(face.box.top, 0)} '
                '${f(face.box.width, 0)}×${f(face.box.height, 0)} px',
          if (face != null && a != null)
            'Centro: (${f(face.box.center.dx, 0)}, ${f(face.box.center.dy, 0)}) px  '
                '= (${f(face.box.center.dx / a.imageSize.width, 2)}, '
                '${f(face.box.center.dy / a.imageSize.height, 2)})',
          'Proporção rosto/largura: ${f(v?.faceWidthRatio, 2)}',
          'Desvio do centro: ${v?.centerOffset == null ? '—' : '${f(v!.centerOffset!.dx, 2)}, ${f(v.centerOffset!.dy, 2)}'}',
          'Centralizado: ${v == null ? '—' : (v.isCentered ? 'sim' : 'não')}',
          'Estável: ${analyzer.stability.isStable ? 'sim (${analyzer.stability.stableFor.inMilliseconds} ms)' : 'não'}',
          'Luminância média: ${f(a?.meanLuma, 0)}',
          'Processamento: ${(m.lastProcessing.inMicroseconds / 1000).toStringAsFixed(1)} ms '
              '(média ${m.averageProcessingMs.toStringAsFixed(1)} ms)',
          'FPS de análise: ${m.analysisFps.toStringAsFixed(1)}  '
              '(descartados ${m.framesDropped}/${m.framesReceived})',
          'Preview: ${preview == null ? '—' : '${preview.width.toInt()}×${preview.height.toInt()}'}  '
              'Quadro: ${a?.sensorSize == null ? '—' : '${a!.sensorSize!.width.toInt()}×${a.sensorSize!.height.toInt()}'}  '
              'rot ${a?.rotationDegrees ?? '—'}°',
          'Câmera: ${session.camera.isFront ? 'frontal' : 'traseira'}, '
              'sensor ${session.camera.sensorOrientation}°',
          'Captura automática: desativada nesta tela',
          'Validação: ${v == null ? '—' : v.status.name} — ${v?.message ?? ''}',
        ];

        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(160),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            lines.join('\n'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontFamily: 'monospace',
              height: 1.3,
            ),
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.overlay,
    required this.showInfo,
    required this.session,
    required this.onOverlay,
    required this.onShowInfo,
  });

  final OverlayOptions overlay;
  final bool showInfo;
  final LiveFaceSession session;
  final ValueChanged<OverlayOptions> onOverlay;
  final ValueChanged<bool> onShowInfo;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool value, ValueChanged<bool> onChanged) =>
        FilterChip(label: Text(label), selected: value, onSelected: onChanged);
    return Container(
      color: Colors.black.withAlpha(170),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                chip(
                  'Caixa',
                  overlay.showBox,
                  (v) => onOverlay(overlay.copyWith(showBox: v)),
                ),
                chip('Contornos', overlay.showContours, (v) async {
                  onOverlay(overlay.copyWith(showContours: v));
                  // Contornos exigem reconfigurar o detector.
                  await session.detector.updateConfig(
                    session.detector.config.copyWith(enableContours: v),
                  );
                  if (v && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Com contornos ativos o ML Kit analisa apenas o '
                          'rosto mais proeminente: múltiplos rostos não são '
                          'detectados.',
                        ),
                      ),
                    );
                  }
                }),
                chip(
                  'Pontos',
                  overlay.showLandmarks,
                  (v) => onOverlay(overlay.copyWith(showLandmarks: v)),
                ),
                chip(
                  'Moldura',
                  overlay.showOval,
                  (v) => onOverlay(overlay.copyWith(showOval: v)),
                ),
                chip('Informações', showInfo, onShowInfo),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => ThresholdsSheet(session: session),
              ),
              icon: const Icon(Icons.tune),
              label: const Text('Ajustar limites e calibrar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Controles para ajustar limites de posição/rotação em tempo de execução.
class ThresholdsSheet extends StatelessWidget {
  const ThresholdsSheet({super.key, required this.session});
  final LiveFaceSession session;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListenableBuilder(
        listenable: thresholdsStore,
        builder: (context, _) {
          final t = thresholdsStore.value;
          void set(DetectionThresholds n) => thresholdsStore.value = n;

          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              _CalibrationCard(session: session),
              const _Section('Centralização e tamanho'),
              _Slider(
                'Tolerância X do centro',
                t.centerToleranceX,
                0.02,
                0.3,
                (v) => set(t.copyWith(centerToleranceX: v)),
              ),
              _Slider(
                'Tolerância Y do centro',
                t.centerToleranceY,
                0.02,
                0.3,
                (v) => set(t.copyWith(centerToleranceY: v)),
              ),
              _Slider(
                'Proporção mínima do rosto',
                t.minFaceWidthRatio,
                0.1,
                0.8,
                (v) => set(t.copyWith(minFaceWidthRatio: v)),
              ),
              _Slider(
                'Proporção máxima do rosto',
                t.maxFaceWidthRatio,
                0.2,
                1.0,
                (v) => set(t.copyWith(maxFaceWidthRatio: v)),
              ),
              _Slider(
                'Largura da moldura',
                t.ovalWidthFraction,
                0.4,
                0.95,
                (v) => set(t.copyWith(ovalWidthFraction: v)),
              ),
              _Slider(
                'Centro vertical da moldura',
                t.ovalCenterY,
                0.3,
                0.6,
                (v) => set(t.copyWith(ovalCenterY: v)),
              ),
              const _Section('Pose frontal (graus)'),
              _Slider(
                'Máx. |X|',
                t.frontalMaxX,
                2,
                30,
                (v) => set(t.copyWith(frontalMaxX: v)),
                decimals: 0,
              ),
              _Slider(
                'Máx. |Y|',
                t.frontalMaxY,
                2,
                30,
                (v) => set(t.copyWith(frontalMaxY: v)),
                decimals: 0,
              ),
              _Slider(
                'Máx. |Z|',
                t.frontalMaxZ,
                2,
                30,
                (v) => set(t.copyWith(frontalMaxZ: v)),
                decimals: 0,
              ),
              const _Section('Laterais e cima/baixo (graus)'),
              _Slider(
                'Lateral: mín. |Y|',
                t.sideMinY,
                5,
                45,
                (v) => set(t.copyWith(sideMinY: v)),
                decimals: 0,
              ),
              _Slider(
                'Lateral: máx. |Y|',
                t.sideMaxY,
                10,
                60,
                (v) => set(t.copyWith(sideMaxY: v)),
                decimals: 0,
              ),
              _Slider(
                'Cima/baixo: mín. |X|',
                t.pitchMin,
                5,
                40,
                (v) => set(t.copyWith(pitchMin: v)),
                decimals: 0,
              ),
              _Slider(
                'Cima/baixo: máx. |X|',
                t.pitchMax,
                10,
                50,
                (v) => set(t.copyWith(pitchMax: v)),
                decimals: 0,
              ),
              const _Section('Estabilidade, tempo e iluminação'),
              _Slider(
                'Tempo de espera (ms)',
                t.holdDurationMs.toDouble(),
                200,
                2000,
                (v) => set(t.copyWith(holdDurationMs: v.round())),
                decimals: 0,
              ),
              _Slider(
                'Movimento máx. entre quadros',
                t.stabilityMaxMovement,
                0.005,
                0.1,
                (v) => set(t.copyWith(stabilityMaxMovement: v)),
                decimals: 3,
              ),
              _Slider(
                'Variação máx. de ângulo (°)',
                t.stabilityMaxAngleDelta,
                1,
                15,
                (v) => set(t.copyWith(stabilityMaxAngleDelta: v)),
                decimals: 0,
              ),
              _Slider(
                'Luminância mínima',
                t.minLuma,
                0,
                120,
                (v) => set(t.copyWith(minLuma: v)),
                decimals: 0,
              ),
              _Slider(
                'Luminância máxima',
                t.maxLuma,
                150,
                255,
                (v) => set(t.copyWith(maxLuma: v)),
                decimals: 0,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: thresholdsStore.reset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Restaurar valores padrão'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Calibra o sentido real de Euler Y/X com o próprio usuário, em vez de
/// depender de sinais fixos.
class _CalibrationCard extends StatelessWidget {
  const _CalibrationCard({required this.session});
  final LiveFaceSession session;

  @override
  Widget build(BuildContext context) {
    final t = thresholdsStore.value;
    void calibrate({required bool yaw}) {
      final v = session.analyzer.validation;
      final face = v?.face;
      final angle = yaw ? face?.eulerY : face?.eulerX;
      String msg;
      if (angle == null || angle.abs() < 8) {
        msg =
            'Ângulo insuficiente (precisa |${yaw ? 'Y' : 'X'}| ≥ 8°). '
            'Mantenha a pose e tente de novo.';
      } else {
        final sign = angle > 0 ? 1 : -1;
        thresholdsStore.value = yaw
            ? t.copyWith(yawSignForUserRight: sign)
            : t.copyWith(pitchSignForUp: sign);
        msg =
            'Calibrado: ${yaw ? 'Y' : 'X'} = ${angle.toStringAsFixed(1)}° '
            '→ sinal ${sign > 0 ? '+' : '−'}';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Calibração de sentido',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Sinal atual: virar à direita ⇒ Y '
              '${t.yawSignForUserRight > 0 ? 'positivo' : 'negativo'}; '
              'olhar para cima ⇒ X '
              '${t.pitchSignForUp > 0 ? 'positivo' : 'negativo'}.\n'
              'Vire a cabeça para a SUA direita (ou olhe para cima), mantenha '
              'e toque no botão correspondente.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => calibrate(yaw: true),
                  child: const Text('Estou virado à direita'),
                ),
                OutlinedButton(
                  onPressed: () => calibrate(yaw: false),
                  child: const Text('Estou olhando para cima'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Slider extends StatelessWidget {
  const _Slider(
    this.label,
    this.value,
    this.min,
    this.max,
    this.onChanged, {
    this.decimals = 2,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 5, child: Text(label)),
        Expanded(
          flex: 6,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            value.toStringAsFixed(decimals),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
