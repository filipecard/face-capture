import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/capture_storage_service.dart';
import '../services/face_comparison_service.dart';
import '../services/image_processing_service.dart';
import 'guided_capture_page.dart';
import 'region_select_page.dart';

/// Comparação facial entre a foto de um documento (RG/CNH) e a selfie
/// frontal capturada no laboratório.
class DocumentComparisonPage extends StatefulWidget {
  const DocumentComparisonPage({super.key});

  @override
  State<DocumentComparisonPage> createState() => _DocumentComparisonPageState();
}

class _Side {
  PreparedImage? image;
  Uint8List? faceThumb;
  FaceEmbeddingResult? result;
}

class _DocumentComparisonPageState extends State<DocumentComparisonPage> {
  static const _storage = CaptureStorageService();
  static const _images = ImageProcessingService();
  final _service = FaceComparisonService();
  final _picker = ImagePicker();

  File? _selfieFile;
  final _doc = _Side();
  final _selfie = _Side();

  bool _modelLoading = true;
  bool _busy = false;
  String _stage = '';
  String? _error;
  double? _similarity;
  Duration? _totalTime;

  @override
  void initState() {
    super.initState();
    _loadSelfie();
    _service.initialize().then((_) {
      if (mounted) setState(() => _modelLoading = false);
    });
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadSelfie() async {
    final f = await _storage.latestFrontal();
    if (mounted) {
      setState(() {
        _selfieFile = f;
        _selfie.result = null;
        _selfie.faceThumb = null;
        _similarity = null;
      });
    }
  }

  Future<void> _captureSelfie() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const GuidedCapturePage()));
    await _loadSelfie();
  }

  Future<void> _pickDocument(ImageSource source) async {
    final XFile? file = await _picker.pickImage(source: source);
    if (file == null || !mounted) return;
    setState(() {
      _busy = true;
      _stage = 'Corrigindo orientação da imagem...';
      _error = null;
    });
    try {
      final prepared = await _images.prepare(await file.readAsBytes());
      if (!mounted) return;
      setState(() => _busy = false);
      final rect = await Navigator.of(context).push<Rect>(
        MaterialPageRoute(builder: (_) => RegionSelectPage(image: prepared)),
      );
      if (rect == null || !mounted) return;
      setState(() {
        _busy = true;
        _stage = 'Recortando a região selecionada...';
      });
      final cropped = await _images.crop(prepared, rect);
      setState(() {
        _doc.image = cropped;
        _doc.result = null;
        _doc.faceThumb = null;
        _similarity = null;
      });
    } catch (e) {
      setState(() => _error = 'Falha ao preparar o documento: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compare() async {
    final selfieFile = _selfieFile;
    final docImage = _doc.image;
    if (selfieFile == null || docImage == null) return;
    final total = Stopwatch()..start();
    setState(() {
      _busy = true;
      _error = null;
      _similarity = null;
    });
    try {
      setState(() => _stage = 'Preparando a selfie...');
      final selfieImage = await _images.prepare(await selfieFile.readAsBytes());
      _selfie.image = selfieImage;

      setState(
        () => _stage = 'Detectando rosto e extraindo embedding (documento)...',
      );
      final docResult = await _service.extract(docImage, 'documento');
      setState(
        () => _stage = 'Detectando rosto e extraindo embedding (selfie)...',
      );
      final selfieResult = await _service.extract(selfieImage, 'selfie');

      setState(() => _stage = 'Calculando similaridade...');
      final sim = FaceComparisonService.cosineSimilarity(
        docResult.embedding,
        selfieResult.embedding,
      );
      final docThumb = await _images.cropFaceThumbnail(
        docImage.bytes,
        docResult.faceBox,
      );
      final selfieThumb = await _images.cropFaceThumbnail(
        selfieImage.bytes,
        selfieResult.faceBox,
      );
      if (!mounted) return;
      setState(() {
        _doc
          ..result = docResult
          ..faceThumb = docThumb;
        _selfie
          ..result = selfieResult
          ..faceThumb = selfieThumb;
        _similarity = sim;
        _totalTime = total.elapsed;
      });
    } on NoFaceFoundException catch (e) {
      setState(() => _error = '$e Ajuste a região ou use outra imagem.');
    } catch (e) {
      setState(() => _error = 'Falha no processamento: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canCompare =
        _service.isReady && _selfieFile != null && _doc.image != null && !_busy;

    return Scaffold(
      appBar: AppBar(title: const Text('Comparação com documento')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ModelStatus(loading: _modelLoading, service: _service),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ImageCard(
                    title: '1. Documento',
                    image: _doc.image == null
                        ? null
                        : Image.memory(_doc.image!.bytes, fit: BoxFit.cover),
                    face: _doc.faceThumb,
                    actions: [
                      _SmallButton(
                        icon: Icons.photo_camera,
                        label: 'Fotografar',
                        onPressed: _busy
                            ? null
                            : () => _pickDocument(ImageSource.camera),
                      ),
                      _SmallButton(
                        icon: Icons.photo_library,
                        label: 'Galeria',
                        onPressed: _busy
                            ? null
                            : () => _pickDocument(ImageSource.gallery),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ImageCard(
                    title: '2. Selfie frontal',
                    image: _selfieFile == null
                        ? null
                        : Image.file(
                            _selfieFile!,
                            fit: BoxFit.cover,
                            cacheWidth: 400,
                          ),
                    face: _selfie.faceThumb,
                    actions: [
                      _SmallButton(
                        icon: Icons.face,
                        label: _selfieFile == null ? 'Capturar' : 'Nova selfie',
                        onPressed: _busy ? null : _captureSelfie,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: canCompare ? _compare : null,
              icon: const Icon(Icons.compare),
              label: const Text('3. Comparar'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_stage, textAlign: TextAlign.center),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_similarity != null) ...[
              const SizedBox(height: 16),
              _ResultCard(
                similarity: _similarity!,
                doc: _doc.result!,
                selfie: _selfie.result!,
                docImage: _doc.image!,
                selfieImage: _selfie.image!,
                total: _totalTime,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'As imagens do documento ficam apenas na memória desta tela e '
              'não são gravadas. Nada é enviado para fora do aparelho.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelStatus extends StatelessWidget {
  const _ModelStatus({required this.loading, required this.service});
  final bool loading;
  final FaceComparisonService service;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (loading) {
      return const ListTile(
        leading: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Carregando modelo MobileFaceNet...'),
      );
    }
    if (!service.isReady) {
      return Card(
        color: scheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.block),
          title: const Text('Comparação biométrica indisponível'),
          subtitle: Text(
            'O modelo não pôde ser carregado neste aparelho: '
            '${service.initError}',
          ),
        ),
      );
    }
    return ListTile(
      leading: Icon(Icons.check_circle, color: scheme.primary),
      title: const Text('Modelo carregado: MobileFaceNet (192 dimensões)'),
      subtitle: Text(
        'face_detection_tflite 6.8.0 · carga em '
        '${service.initTime?.inMilliseconds ?? '—'} ms',
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.title,
    required this.image,
    required this.face,
    required this.actions,
  });
  final String title;
  final Widget? image;
  final Uint8List? face;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                image ??
                    const ColoredBox(
                      color: Colors.black12,
                      child: Icon(Icons.image_outlined, size: 48),
                    ),
                if (face != null)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    width: 64,
                    height: 80,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Image.memory(face!, fit: BoxFit.cover),
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.similarity,
    required this.doc,
    required this.selfie,
    required this.docImage,
    required this.selfieImage,
    required this.total,
  });
  final double similarity;
  final FaceEmbeddingResult doc;
  final FaceEmbeddingResult selfie;
  final PreparedImage docImage;
  final PreparedImage selfieImage;
  final Duration? total;

  String _tech(String label, FaceEmbeddingResult r, PreparedImage img) =>
      '$label: imagem ${img.width}×${img.height} px, '
      '${r.faceCount} rosto(s), rosto ${r.faceBox.width.round()}×'
      '${r.faceBox.height.round()} px, confiança '
      '${r.detectionScore.toStringAsFixed(2)}, yaw '
      '${r.yaw?.toStringAsFixed(1) ?? '—'}°, detecção '
      '${r.detectTime.inMilliseconds} ms, embedding '
      '${r.embedTime.inMilliseconds} ms, dim ${r.embedding.length}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issues = [
      for (final i in doc.issues) 'Documento: ${qualityIssueText(i)}',
      for (final i in selfie.issues) 'Selfie: ${qualityIssueText(i)}',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Similaridade cosseno', style: theme.textTheme.titleMedium),
            Text(
              similarity.toStringAsFixed(4),
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Escala de −1 a 1. Este valor NÃO é uma probabilidade de se '
              'tratar da mesma pessoa e não há limiar de aprovação calibrado '
              'para documentos. Use apenas para comparação experimental.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            Text('Problemas de qualidade', style: theme.textTheme.titleSmall),
            Text(issues.isEmpty ? 'Nenhum identificado.' : issues.join('\n')),
            const Divider(height: 24),
            Text('Estado técnico', style: theme.textTheme.titleSmall),
            Text(
              '${_tech('Documento', doc, docImage)}\n'
              '${_tech('Selfie', selfie, selfieImage)}\n'
              'Tempo total: ${total?.inMilliseconds ?? '—'} ms',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
