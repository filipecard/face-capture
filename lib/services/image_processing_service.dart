import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

/// Imagem JPEG já na orientação correta (EXIF aplicado), com dimensões.
class PreparedImage {
  const PreparedImage(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Rotação, recorte e redimensionamento de imagens estáticas.
///
/// Todo o trabalho pesado (decodificar/codificar JPEG) roda em um isolate
/// separado via [Isolate.run], fora da thread de interface.
class ImageProcessingService {
  const ImageProcessingService();

  /// Aplica a orientação EXIF aos pixels e limita o maior lado a
  /// [maxSide] px (fotos de câmera chegam a 12+ MP, desnecessário aqui).
  Future<PreparedImage> prepare(Uint8List bytes, {int maxSide = 2000}) {
    return Isolate.run(() => prepareSync(bytes, maxSide: maxSide));
  }

  /// Recorta a região [normRect] (coordenadas 0–1) de uma imagem preparada.
  Future<PreparedImage> crop(PreparedImage src, Rect normRect) {
    final bytes = src.bytes;
    final l = normRect.left, t = normRect.top;
    final w = normRect.width, h = normRect.height;
    return Isolate.run(() => cropSync(bytes, Rect.fromLTWH(l, t, w, h)));
  }

  /// Versão síncrona de [prepare] (exposta para testes).
  static PreparedImage prepareSync(Uint8List bytes, {int maxSide = 2000}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Formato de imagem não suportado.');
    }
    var image = img.bakeOrientation(decoded);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxSide)
          : img.copyResize(image, height: maxSide);
    }
    return PreparedImage(
      img.encodeJpg(image, quality: 95),
      image.width,
      image.height,
    );
  }

  /// Versão síncrona de [crop] (exposta para testes).
  static PreparedImage cropSync(Uint8List bytes, Rect normRect) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('Formato de imagem não suportado.');
    }
    final r = pixelRect(normRect, image.width, image.height);
    final out = img.copyCrop(
      image,
      x: r.left.round(),
      y: r.top.round(),
      width: r.width.round(),
      height: r.height.round(),
    );
    return PreparedImage(
      img.encodeJpg(out, quality: 95),
      out.width,
      out.height,
    );
  }

  /// Converte um retângulo normalizado em pixels, limitado à imagem e com
  /// pelo menos 1 px de lado.
  static Rect pixelRect(Rect norm, int width, int height) {
    double c(double v) => v.clamp(0.0, 1.0);
    final l = c(norm.left) * width;
    final t = c(norm.top) * height;
    final r = c(norm.right) * width;
    final b = c(norm.bottom) * height;
    return Rect.fromLTRB(l, t, r - l < 1 ? l + 1 : r, b - t < 1 ? t + 1 : b);
  }

  /// Recorta o retângulo [box] (pixels) com margem relativa [padding],
  /// para exibir o rosto detectado.
  Future<Uint8List> cropFaceThumbnail(
    Uint8List bytes,
    Rect box, {
    double padding = 0.25,
  }) {
    final l = box.left, t = box.top, w = box.width, h = box.height;
    return Isolate.run(() {
      final image = img.decodeImage(bytes)!;
      final px = w * padding, py = h * padding;
      final norm = Rect.fromLTRB(
        (l - px) / image.width,
        (t - py) / image.height,
        (l + w + px) / image.width,
        (t + h + py) / image.height,
      );
      final r = pixelRect(norm, image.width, image.height);
      var out = img.copyCrop(
        image,
        x: r.left.round(),
        y: r.top.round(),
        width: r.width.round(),
        height: r.height.round(),
      );
      if (out.width > 320) out = img.copyResize(out, width: 320);
      return img.encodeJpg(out, quality: 90);
    });
  }
}
