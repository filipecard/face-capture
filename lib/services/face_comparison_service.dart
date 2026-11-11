import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:face_detection_tflite/face_detection_tflite.dart' as fdt;

import 'image_processing_service.dart';

/// Problemas de qualidade identificados em uma imagem de rosto.
enum FaceQualityIssue {
  multipleFaces,
  smallFace,
  lowDetectionScore,
  nonFrontalPose,
}

String qualityIssueText(FaceQualityIssue i) {
  switch (i) {
    case FaceQualityIssue.multipleFaces:
      return 'Mais de um rosto encontrado; foi usado o maior.';
    case FaceQualityIssue.smallFace:
      return 'Rosto com baixa resolução (menos de ${FaceComparisonService.minFacePx} px de largura).';
    case FaceQualityIssue.lowDetectionScore:
      return 'Confiança da detecção baixa.';
    case FaceQualityIssue.nonFrontalPose:
      return 'Rosto não frontal (rotação acima de 20°).';
  }
}

/// Embedding extraído de uma imagem, com metadados técnicos.
class FaceEmbeddingResult {
  const FaceEmbeddingResult({
    required this.embedding,
    required this.faceBox,
    required this.faceCount,
    required this.detectionScore,
    required this.yaw,
    required this.issues,
    required this.detectTime,
    required this.embedTime,
  });

  final Float32List embedding;
  final Rect faceBox;
  final int faceCount;
  final double detectionScore;
  final double? yaw;
  final List<FaceQualityIssue> issues;
  final Duration detectTime;
  final Duration embedTime;
}

class NoFaceFoundException implements Exception {
  NoFaceFoundException(this.label);
  final String label;
  @override
  String toString() => 'Nenhum rosto encontrado em: $label.';
}

/// Extração de embeddings faciais e comparação por similaridade cosseno.
///
/// Usa o pacote `face_detection_tflite` 6.8.0, que traz o modelo
/// `mobilefacenet.tflite` (MobileFaceNets, arXiv 1804.07573; 192 dimensões;
/// Apache 2.0 segundo o pacote). Pré-processamento feito pelo pacote:
/// alinhamento pelos olhos (rotação + escala; não corrige yaw/pitch), recorte
/// 112×112, RGB normalizado para [-1, 1] (x/127,5 − 1) e saída normalizada L2.
///
/// Inferência roda em um isolate do próprio pacote.
///
/// O valor de similaridade é uma medida geométrica entre vetores. **Não** é
/// probabilidade de identidade e não há limiar de aprovação calibrado.
class FaceComparisonService {
  static const int minFacePx = 80;
  static const double minScore = 0.7;
  static const double maxYaw = 20;

  fdt.FaceDetector? _detector;
  Duration? initTime;
  Object? initError;

  bool get isReady => _detector?.isReady ?? false;

  /// Carrega os modelos. Em caso de falha, [initError] explica o motivo e a
  /// comparação fica indisponível (nenhum resultado é simulado).
  Future<bool> initialize() async {
    if (isReady) return true;
    final sw = Stopwatch()..start();
    try {
      _detector = await fdt.FaceDetector.create();
      initTime = sw.elapsed;
      return true;
    } catch (e) {
      initError = e;
      _detector = null;
      return false;
    }
  }

  /// Detecta o rosto principal em [image] e extrai seu embedding.
  Future<FaceEmbeddingResult> extract(PreparedImage image, String label) async {
    final d = _detector;
    if (d == null || !d.isReady) {
      throw StateError('Modelo de comparação não carregado.');
    }
    final sw = Stopwatch()..start();
    final faces = await d.detectFacesFromBytes(
      image.bytes,
      mode: fdt.FaceDetectionMode.full,
    );
    final detectTime = sw.elapsed;
    if (faces.isEmpty) throw NoFaceFoundException(label);

    final face = faces.reduce(
      (a, b) =>
          a.boundingBox.width * a.boundingBox.height >=
              b.boundingBox.width * b.boundingBox.height
          ? a
          : b,
    );

    sw
      ..reset()
      ..start();
    final embedding = await d.getFaceEmbedding(face, image.bytes);
    final embedTime = sw.elapsed;

    final b = face.boundingBox;
    final yaw = face.headEulerAngles?.y;
    final issues = <FaceQualityIssue>[
      if (faces.length > 1) FaceQualityIssue.multipleFaces,
      if (b.width < minFacePx) FaceQualityIssue.smallFace,
      if (face.score < minScore) FaceQualityIssue.lowDetectionScore,
      if (yaw != null && yaw.abs() > maxYaw) FaceQualityIssue.nonFrontalPose,
    ];

    return FaceEmbeddingResult(
      embedding: embedding,
      faceBox: Rect.fromLTRB(b.left, b.top, b.right, b.bottom),
      faceCount: faces.length,
      detectionScore: face.score,
      yaw: yaw,
      issues: issues,
      detectTime: detectTime,
      embedTime: embedTime,
    );
  }

  /// Similaridade cosseno entre dois vetores (−1 a 1).
  ///
  /// Implementação própria (testada), independente do pacote.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Vetores com dimensões diferentes.');
    }
    if (a.isEmpty) throw ArgumentError('Vetores vazios.');
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) {
      throw ArgumentError('Vetor com norma zero.');
    }
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  Future<void> dispose() async {
    final d = _detector;
    _detector = null;
    await d?.dispose();
  }
}
