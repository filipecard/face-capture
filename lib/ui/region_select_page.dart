import 'package:flutter/material.dart';

import '../services/image_processing_service.dart';

/// Seleção manual da região da fotografia no documento.
///
/// Arraste o retângulo para mover e a alça do canto para redimensionar.
/// Retorna o retângulo em coordenadas normalizadas (0–1).
class RegionSelectPage extends StatefulWidget {
  const RegionSelectPage({super.key, required this.image});
  final PreparedImage image;

  @override
  State<RegionSelectPage> createState() => _RegionSelectPageState();
}

class _RegionSelectPageState extends State<RegionSelectPage> {
  Rect _rect = const Rect.fromLTWH(0.1, 0.2, 0.35, 0.45);
  static const _minSide = 0.05;

  void _move(Offset deltaNorm) {
    var r = _rect.shift(deltaNorm);
    final dx = r.left < 0 ? -r.left : (r.right > 1 ? 1 - r.right : 0.0);
    final dy = r.top < 0 ? -r.top : (r.bottom > 1 ? 1 - r.bottom : 0.0);
    r = r.shift(Offset(dx, dy));
    setState(() => _rect = r);
  }

  void _resize(Offset deltaNorm) {
    final right = (_rect.right + deltaNorm.dx).clamp(
      _rect.left + _minSide,
      1.0,
    );
    final bottom = (_rect.bottom + deltaNorm.dy).clamp(
      _rect.top + _minSide,
      1.0,
    );
    setState(() => _rect = Rect.fromLTRB(_rect.left, _rect.top, right, bottom));
  }

  @override
  Widget build(BuildContext context) {
    final img = widget.image;
    final aspect = img.width / img.height;
    final cropPx = ImageProcessingService.pixelRect(
      _rect,
      img.width,
      img.height,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Selecione a foto do documento')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Ajuste o retângulo sobre a fotografia do rosto no documento. '
                'Arraste para mover; use o canto inferior direito para '
                'redimensionar.',
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final w = box.maxWidth, h = box.maxHeight;
                      final r = Rect.fromLTRB(
                        _rect.left * w,
                        _rect.top * h,
                        _rect.right * w,
                        _rect.bottom * h,
                      );
                      Offset norm(Offset d) => Offset(d.dx / w, d.dy / h);
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: Image.memory(img.bytes, fit: BoxFit.fill),
                          ),
                          Positioned.fromRect(
                            rect: r,
                            child: GestureDetector(
                              onPanUpdate: (d) => _move(norm(d.delta)),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.amber,
                                    width: 3,
                                  ),
                                  color: Colors.amber.withAlpha(30),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: r.right - 22,
                            top: r.bottom - 22,
                            child: GestureDetector(
                              onPanUpdate: (d) => _resize(norm(d.delta)),
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: Colors.amber,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.black,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            Text('Região: ${cropPx.width.round()}×${cropPx.height.round()} px'),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(_rect),
                icon: const Icon(Icons.crop),
                label: const Text('Usar esta região'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
