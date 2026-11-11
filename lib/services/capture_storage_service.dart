import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'face_capture_controller.dart';
import 'face_position_validator.dart';

/// Armazena capturas apenas no diretório privado do aplicativo.
///
/// Nada é enviado para fora do aparelho nem copiado para a galeria.
class CaptureStorageService {
  const CaptureStorageService();

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}captures');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Move a foto temporária da câmera para o armazenamento privado.
  Future<CapturedPhoto> persist(
    String tempPath,
    PoseTarget target,
    Duration captureTime,
  ) async {
    final sw = Stopwatch()..start();
    final dir = await _dir();
    final name = '${target.name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest = '${dir.path}${Platform.pathSeparator}$name';
    final src = File(tempPath);
    try {
      await src.rename(dest);
    } on FileSystemException {
      // Diretórios em volumes diferentes: copia e apaga o temporário.
      await src.copy(dest);
      await src.delete();
    }
    return CapturedPhoto(
      target: target,
      path: dest,
      captureTime: captureTime,
      saveTime: sw.elapsed,
    );
  }

  /// Captura frontal mais recente (usada na comparação com documento).
  Future<File?> latestFrontal() async {
    final dir = await _dir();
    final files = await dir
        .list()
        .where(
          (e) =>
              e is File &&
              e.uri.pathSegments.last.startsWith('${PoseTarget.frontal.name}_'),
        )
        .cast<File>()
        .toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => b.path.compareTo(a.path));
    return files.first;
  }

  Future<int> count() async {
    final dir = await _dir();
    return dir.list().where((e) => e is File).length;
  }

  /// Apaga todas as capturas. Retorna quantos arquivos foram removidos.
  Future<int> deleteAll() async {
    final dir = await _dir();
    var n = 0;
    await for (final e in dir.list()) {
      if (e is File) {
        await e.delete();
        n++;
      }
    }
    return n;
  }
}
