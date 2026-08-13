import 'package:flutter/material.dart';

import '../../llm/structured_note.dart';
import '../../theme/tiza_theme.dart';

/// La nota estructurada, renderizada.
///
/// Es lo que pide el paso 5 y es lo contrario del visor de markdown crudo del
/// paso 4: acá ya no se está inspeccionando la respuesta del modelo, se está
/// leyendo la nota. Que se pueda renderizar con widgets nativos y no con un
/// parser de markdown es justamente el resultado de haber impuesto el schema —
/// llegan datos, no texto que haya que interpretar.
///
/// No usa ningún paquete de markdown: `flutter_markdown` está discontinuado y,
/// más importante, no haría falta ni existiendo. Los datos ya vienen tipados.
class StructuredNoteView extends StatelessWidget {
  const StructuredNoteView({super.key, required this.note});

  final StructuredNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.tiza;

    if (note.isEmpty) {
      return Text(
        'El modelo devolvió una nota vacía.',
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note.title != null) ...[
          Text(note.title!, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 18),
        ],
        for (final section in note.sections) ...[
          if (section.heading.isNotEmpty)
            Padding(
              // El sangrado refleja `depth` sin anidar widgets: la estructura de
              // datos es chata y el render también.
              padding: EdgeInsets.only(left: section.depth * 14.0, bottom: 8),
              child: Text(
                section.heading,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: kSerif,
                  fontSize: 17,
                ),
              ),
            ),
          for (final bullet in section.bullets)
            _Bullet(text: bullet, indent: section.depth * 14.0),
          const SizedBox(height: 16),
        ],
        if (note.actionItems.isNotEmpty) ...[
          Divider(height: 1, color: palette.rule),
          const SizedBox(height: 14),
          Text('ACTION ITEMS', style: theme.textTheme.labelSmall),
          const SizedBox(height: 10),
          for (final item in note.actionItems) _Action(item: item),
        ],
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, required this.indent});

  final String text;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 9, left: 2),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: palette.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.item});

  final ActionItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.tiza;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 9),
            child: Icon(
              Icons.check_box_outline_blank,
              size: 15,
              color: palette.inkFaint,
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (item.owner != null)
                    TextSpan(
                      // El responsable en terracota y no en negrita: distingue sin
                      // gritar, y deja claro cuáles tareas tienen dueño asignado y
                      // cuáles no.
                      text: '${item.owner}  ',
                      style: TextStyle(
                        color: palette.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  TextSpan(text: item.text),
                ],
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
