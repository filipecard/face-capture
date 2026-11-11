import 'package:flutter/material.dart';

import '../services/capture_storage_service.dart';
import 'diagnostics_page.dart';
import 'document_comparison_page.dart';
import 'guided_capture_page.dart';
import 'multi_angle_capture_page.dart';

/// Tela inicial com as quatro opções do laboratório.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Face Capture Lab')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Aplicação experimental para testes de captura facial. '
              'Não é um sistema de autenticação biométrica certificado.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _OptionButton(
              icon: Icons.face_retouching_natural,
              title: 'Captura facial orientada',
              subtitle: 'Moldura, instruções e captura automática',
              onTap: () => _open(context, const GuidedCapturePage()),
            ),
            _OptionButton(
              icon: Icons.threesixty,
              title: 'Captura de múltiplos ângulos',
              subtitle: 'Frontal, direita, esquerda (cima/baixo opcional)',
              onTap: () => _open(context, const MultiAngleCapturePage()),
            ),
            _OptionButton(
              icon: Icons.badge_outlined,
              title: 'Comparação facial com documento',
              subtitle: 'RG/CNH × selfie frontal (embeddings)',
              onTap: () => _open(context, const DocumentComparisonPage()),
            ),
            _OptionButton(
              icon: Icons.monitor_heart_outlined,
              title: 'Diagnóstico da câmera e detecção',
              subtitle: 'Ângulos, métricas e ajuste de limites',
              onTap: () => _open(context, const DiagnosticsPage()),
            ),
            const SizedBox(height: 8),
            const _DeleteCapturesButton(),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card.filled(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              children: [
                Icon(icon, size: 36, color: scheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Apaga todas as capturas do armazenamento privado, após confirmação.
class _DeleteCapturesButton extends StatelessWidget {
  const _DeleteCapturesButton();

  static const _storage = CaptureStorageService();

  Future<void> _confirmAndDelete(BuildContext context) async {
    final n = await _storage.count();
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir todas as capturas?'),
        content: Text(
          n == 0
              ? 'Não há capturas salvas.'
              : '$n arquivo(s) serão apagados deste aparelho. '
                    'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          if (n > 0)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir'),
            ),
        ],
      ),
    );
    if (ok != true) return;
    final removed = await _storage.deleteAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$removed captura(s) excluída(s).')));
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _confirmAndDelete(context),
      icon: const Icon(Icons.delete_outline),
      label: const Text('Excluir todas as capturas'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}
