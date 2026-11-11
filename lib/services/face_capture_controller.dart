import 'package:flutter/foundation.dart';

import '../diagnostics/detection_thresholds.dart';
import 'face_position_validator.dart';

/// Estados explícitos da captura.
enum CaptureState {
  idle,
  initializing,
  searchingFace,
  adjustingPosition,
  holdingPosition,
  capturing,
  processing,
  completed,
  error,
}

/// Foto capturada e persistida no armazenamento privado do app.
class CapturedPhoto {
  const CapturedPhoto({
    required this.target,
    required this.path,
    required this.captureTime,
    required this.saveTime,
  });

  final PoseTarget target;
  final String path;

  /// Tempo do `takePicture` (disparo até o arquivo pronto).
  final Duration captureTime;

  /// Tempo para mover o arquivo ao armazenamento privado.
  final Duration saveTime;
}

/// Tira a foto e devolve o caminho temporário.
typedef TakePhoto = Future<String> Function();

/// Persiste a foto temporária e devolve o resultado final.
typedef PersistPhoto =
    Future<CapturedPhoto> Function(
      String tempPath,
      PoseTarget target,
      Duration captureTime,
    );

/// Controla a sequência de capturas automáticas.
///
/// Recebe a validação de cada quadro analisado ([onFrame]) e decide quando
/// capturar: todas as condições atendidas **e** rosto estável, continuamente,
/// por [DetectionThresholds.holdDurationMs]. Não depende de câmera: pode ser
/// exercitado com dados sintéticos.
///
/// Garantias:
/// - nunca há duas capturas simultâneas;
/// - quadros recebidos durante captura/processamento são ignorados.
class FaceCaptureController extends ChangeNotifier {
  FaceCaptureController({
    required List<PoseTarget> steps,
    required this.takePhoto,
    required this.persistPhoto,
    ThresholdsStore? thresholds,
  }) : assert(steps.isNotEmpty),
       steps = List.unmodifiable(steps),
       thresholds = thresholds ?? thresholdsStore,
       _photos = List<CapturedPhoto?>.filled(steps.length, null);

  final List<PoseTarget> steps;
  final TakePhoto takePhoto;
  final PersistPhoto persistPhoto;
  final ThresholdsStore thresholds;

  CaptureState _state = CaptureState.idle;
  int _step = 0;
  Duration? _holdSince;
  double _holdProgress = 0;
  String _message = '';
  String? _error;
  final List<CapturedPhoto?> _photos;
  bool _captureInFlight = false;
  bool _disposed = false;

  CaptureState get state => _state;
  int get stepIndex => _step;
  PoseTarget get currentTarget => steps[_step];

  /// Fração (0–1) do tempo de espera já cumprido.
  double get holdProgress => _holdProgress;
  String get message => _message;
  String? get error => _error;
  List<CapturedPhoto?> get photos => List.unmodifiable(_photos);

  bool get _acceptsFrames =>
      _state == CaptureState.searchingFace ||
      _state == CaptureState.adjustingPosition ||
      _state == CaptureState.holdingPosition;

  /// A câmera está sendo preparada.
  void markInitializing() {
    _set(CaptureState.initializing, 'Iniciando câmera...');
  }

  /// Começa (ou recomeça) a procurar o rosto para o passo atual.
  void start() {
    _holdSince = null;
    _holdProgress = 0;
    _error = null;
    _set(CaptureState.searchingFace, messageFor(PositionIssue.noFace));
  }

  /// Processa o resultado de um quadro analisado.
  void onFrame(
    ValidationResult v, {
    required bool stable,
    required Duration timestamp,
  }) {
    if (!_acceptsFrames || _captureInFlight) return;

    if (v.status == PositionStatus.noFace) {
      _resetHold();
      _set(CaptureState.searchingFace, v.message);
      return;
    }
    if (!v.isOk) {
      _resetHold();
      _set(CaptureState.adjustingPosition, v.message);
      return;
    }
    if (!stable) {
      _resetHold();
      _set(CaptureState.holdingPosition, 'Mantenha essa posição.');
      return;
    }

    final since = _holdSince ??= timestamp;
    final holdMs = thresholds.value.holdDurationMs;
    final elapsed = (timestamp - since).inMilliseconds;
    _holdProgress = holdMs <= 0 ? 1 : (elapsed / holdMs).clamp(0.0, 1.0);

    if (elapsed >= holdMs) {
      _capture();
    } else {
      _set(CaptureState.holdingPosition, 'Mantenha essa posição.');
    }
  }

  Future<void> _capture() async {
    if (_captureInFlight) return;
    _captureInFlight = true;
    final target = currentTarget;
    _set(CaptureState.capturing, 'Capturando...');
    try {
      final sw = Stopwatch()..start();
      final temp = await takePhoto();
      final captureTime = sw.elapsed;
      if (_disposed) return;
      _set(CaptureState.processing, 'Processando...');
      final photo = await persistPhoto(temp, target, captureTime);
      if (_disposed) return;
      _photos[_step] = photo;
      _advance();
    } catch (e) {
      if (_disposed) return;
      _error = e.toString();
      _set(CaptureState.error, 'Falha na captura. Tente novamente.');
    } finally {
      _captureInFlight = false;
    }
  }

  void _advance() {
    _resetHold();
    final next = _photos.indexWhere((p) => p == null);
    if (next == -1) {
      _set(CaptureState.completed, 'Captura concluída.');
    } else {
      _step = next;
      start();
    }
  }

  /// Refaz a captura do passo [index] (as demais são mantidas).
  void retake(int index) {
    if (_captureInFlight) return;
    _photos[index] = null;
    _step = index;
    start();
  }

  /// Descarta todas as fotos desta sequência e recomeça do primeiro passo.
  void restart() {
    if (_captureInFlight) return;
    for (var i = 0; i < _photos.length; i++) {
      _photos[i] = null;
    }
    _step = 0;
    start();
  }

  /// Registra um erro externo (ex.: câmera indisponível).
  void fail(String error) {
    _error = error;
    _set(CaptureState.error, error);
  }

  void _resetHold() {
    _holdSince = null;
    _holdProgress = 0;
  }

  void _set(CaptureState s, String message) {
    final changed = s != _state || message != _message;
    _state = s;
    _message = message;
    // Mesmo sem mudança de estado o progresso pode ter mudado.
    if (changed || s == CaptureState.holdingPosition) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
