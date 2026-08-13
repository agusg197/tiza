import 'package:flutter/material.dart';

import '../../theme/tiza_theme.dart';

/// Estado visible para cuando el OCR corrió bien pero no encontró texto.
///
/// No es un error del programa y por eso no es una nota de error: es un resultado
/// legítimo del camino gratuito, y el panel de métricas de arriba lo demuestra
/// mostrando 0 renglones y el tiempo que tardó. Lo que necesita el usuario acá no
/// es una disculpa, es saber **por qué** puede haber pasado.
///
/// Las cuatro razones están puestas de más a menos frecuente, y la última es una
/// limitación real de MLKit que conviene decir en vez de esconder.
class NoTextState extends StatelessWidget {
  const NoTextState({super.key, required this.onAnotherPhoto});

  final VoidCallback onAnotherPhoto;

  static const List<String> _reasons = [
    'la foto salió movida o fuera de foco',
    'el pizarrón quedó demasiado lejos',
    'hay poca luz, o un reflejo tapando el texto',
    'la letra es cursiva muy ligada: MLKit está entrenado sobre imprenta',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.tiza;

    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.rule),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 10,
            children: [
              Icon(Icons.search_off_outlined, size: 20, color: palette.accent),
              Expanded(
                child: Text(
                  'No encontré texto en esta foto.',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Lo más probable es que:', style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          for (final reason in _reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('· $reason', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onAnotherPhoto,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text('Probar con otra foto'),
          ),
        ],
      ),
    );
  }
}
