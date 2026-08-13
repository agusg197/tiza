import 'package:flutter/material.dart';

import '../../theme/tiza_theme.dart';
import '../screen_error.dart';

/// La nota de error, con sus salidas y con el detalle plegado.
///
/// El detalle arranca oculto y no se elimina: el mensaje amable alcanza para el
/// 90% de los casos, y cuando no alcanza, lo que dijo el proveedor —o el texto que
/// devolvió el modelo— es lo único con lo que se puede entender qué pasó. Tirarlo
/// para que la pantalla quede limpia es el error más común de los estados de
/// error.
class ErrorNote extends StatefulWidget {
  const ErrorNote({
    super.key,
    required this.error,
    required this.onRecovery,
    required this.onDismiss,
  });

  final ScreenError error;
  final ValueChanged<ErrorRecovery> onRecovery;
  final VoidCallback onDismiss;

  @override
  State<ErrorNote> createState() => _ErrorNoteState();
}

class _ErrorNoteState extends State<ErrorNote> {
  bool _showDetail = false;

  static String _labelFor(ErrorRecovery recovery) => switch (recovery) {
    ErrorRecovery.retry => 'Reintentar',
    ErrorRecovery.openSettings => 'Configurar la key',
    ErrorRecovery.useFake => 'Ver una respuesta simulada',
    ErrorRecovery.chooseSmallerModel => 'Elegir otro modelo',
    ErrorRecovery.anotherPhoto => 'Otra foto',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.tiza;
    final error = widget.error;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: palette.accent, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  error.message,
                  style: theme.textTheme.bodySmall?.copyWith(color: palette.ink),
                ),
              ),
              IconButton(
                onPressed: widget.onDismiss,
                icon: const Icon(Icons.close, size: 17),
                color: palette.inkMuted,
                visualDensity: VisualDensity.compact,
                tooltip: 'Descartar',
              ),
            ],
          ),
          if (_showDetail && error.detail != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 12, 8),
              child: SelectableText(
                error.detail!,
                style: TextStyle(
                  fontFamily: kMono,
                  fontSize: 11.5,
                  height: 1.45,
                  color: palette.inkMuted,
                ),
              ),
            ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final recovery in error.recoveries)
                TextButton(
                  onPressed: () => widget.onRecovery(recovery),
                  style: TextButton.styleFrom(
                    // La primera salida es la recomendada y va en terracota; las
                    // demás en gris, para que no compitan.
                    foregroundColor: recovery == error.recoveries.first
                        ? palette.accent
                        : palette.inkMuted,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(_labelFor(recovery)),
                ),
              if (error.detail != null)
                TextButton(
                  onPressed: () => setState(() => _showDetail = !_showDetail),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.inkMuted,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(_showDetail ? 'Ocultar el detalle' : 'Ver el detalle'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
