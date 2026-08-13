import 'package:flutter/material.dart';

import '../../llm/llm_client.dart';
import '../../theme/tiza_theme.dart';
import 'markdown_raw_view.dart';
import 'serialization_view.dart';
import 'structured_note_view.dart';

enum OutputTab { input, reply }

/// Cómo mirar una respuesta con schema: la nota ya armada, o el JSON que llegó.
///
/// Las dos vistas existen porque contestan preguntas distintas. La estructura
/// dice si la nota quedó bien; el JSON dice si el modelo entendió el schema. Con
/// sólo la primera, un error de campos se confunde con un error de contenido.
enum ReplyView { structure, json }

/// El visor con las dos caras de la llamada: lo que entra y lo que sale.
///
/// Tenerlas en el mismo panel, a un toque de distancia, es lo que permite
/// atribuir un error: si el markdown salió mal, la pregunta es si el modelo se
/// equivocó o si la serialización ya venía desordenada, y eso sólo se contesta
/// comparando las dos.
class OutputPanel extends StatelessWidget {
  const OutputPanel({
    super.key,
    required this.tab,
    required this.onTabChanged,
    required this.serialized,
    required this.serializerDescription,
    required this.reply,
    required this.asking,
    required this.replyView,
    required this.onReplyViewChanged,
    this.onExportFixture,
  });

  final OutputTab tab;
  final ValueChanged<OutputTab> onTabChanged;
  final String serialized;
  final String serializerDescription;
  final ModelReply? reply;
  final bool asking;
  final ReplyView replyView;
  final ValueChanged<ReplyView> onReplyViewChanged;

  /// Guarda esta foto como caso del golden set. `null` lo esconde.
  final VoidCallback? onExportFixture;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;

    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.rule),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Tab(
                    label: 'LO QUE VE EL MODELO',
                    selected: tab == OutputTab.input,
                    onTap: () => onTabChanged(OutputTab.input),
                  ),
                ),
                Container(width: 1, color: palette.rule),
                Expanded(
                  child: _Tab(
                    label: 'LO QUE DEVOLVIÓ',
                    selected: tab == OutputTab.reply,
                    onTap: () => onTabChanged(OutputTab.reply),
                    // Un punto en vez de habilitar/deshabilitar: la pestaña se
                    // puede visitar siempre, y el punto dice si hay algo.
                    marked: reply != null,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.rule),
          Expanded(
            child: tab == OutputTab.input
                ? _InputSide(
                    serialized: serialized,
                    description: serializerDescription,
                    onExportFixture: onExportFixture,
                  )
                : _ReplySide(
                    reply: reply,
                    asking: asking,
                    view: replyView,
                    onViewChanged: onReplyViewChanged,
                  ),
          ),
        ],
      ),
    );
  }
}

class _InputSide extends StatelessWidget {
  const _InputSide({
    required this.serialized,
    required this.description,
    this.onExportFixture,
  });

  final String serialized;
  final String description;
  final VoidCallback? onExportFixture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // La explicación del formato vive acá, junto al texto que describe, y no
          // en una franja fija de la pantalla: así no le come alto al visor, que
          // es lo que uno quiere leer.
          Text(description, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('${serialized.length} caracteres', style: theme.textTheme.labelSmall),
              const Spacer(),
              if (onExportFixture != null)
                TextButton(
                  onPressed: onExportFixture,
                  style: TextButton.styleFrom(
                    foregroundColor: context.tiza.accent,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(
                    'GUARDAR COMO FIXTURE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: context.tiza.accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SerializationView(text: serialized),
        ],
      ),
    );
  }
}

class _ReplySide extends StatelessWidget {
  const _ReplySide({
    required this.reply,
    required this.asking,
    required this.view,
    required this.onViewChanged,
  });

  final ModelReply? reply;
  final bool asking;
  final ReplyView view;
  final ValueChanged<ReplyView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.tiza;

    if (asking) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: palette.accent),
            ),
            const SizedBox(height: 14),
            Text('Preguntándole al modelo…', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    final current = reply;
    if (current == null) {
      return _Centered(
        text: 'Todavía no le preguntaste al modelo.\n'
            'Hasta acá no salió nada del teléfono.',
      );
    }

    final showingJson = current.structured && view == ReplyView.json;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (current.structured)
                _ViewSwitch(view: view, onChanged: onViewChanged)
              else
                Text(
                  '${current.markdown.length} caracteres',
                  style: theme.textTheme.labelSmall,
                ),
              const Spacer(),
              if (current.modelVersion != null)
                Flexible(
                  child: Text(
                    current.modelVersion!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: kMono,
                      letterSpacing: 0,
                      color: palette.inkFaint,
                    ),
                  ),
                ),
            ],
          ),
          if (current.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Warnings(warnings: current.warnings),
          ],
          const SizedBox(height: 14),
          if (current.note != null && !showingJson)
            StructuredNoteView(note: current.note!)
          else
            MarkdownRawView(
              markdown: showingJson
                  ? (current.rawJson ?? current.markdown)
                  : current.markdown,
            ),
        ],
      ),
    );
  }
}

/// Lo que descartó la validación estricta.
///
/// Se muestra en vez de silenciarse: la respuesta se usó igual, pero el usuario
/// tiene que poder saber que no llegó entera. Es también el número que el paso 7
/// va a contar por foto.
class _Warnings extends StatelessWidget {
  const _Warnings({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.tiza;

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 6,
            children: [
              Icon(Icons.filter_alt_outlined, size: 13, color: palette.accent),
              Text(
                'VALIDACIÓN ESTRICTA',
                style: theme.textTheme.labelSmall?.copyWith(color: palette.accent),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final warning in warnings)
            Text(
              '· $warning',
              style: theme.textTheme.bodySmall?.copyWith(color: palette.ink),
            ),
        ],
      ),
    );
  }
}

class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.view, required this.onChanged});

  final ReplyView view;
  final ValueChanged<ReplyView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 4,
      children: [
        for (final option in ReplyView.values)
          _ViewChip(
            label: option == ReplyView.structure ? 'ESTRUCTURA' : 'JSON',
            selected: option == view,
            onTap: () => onChanged(option),
          ),
      ],
    );
  }
}

class _ViewChip extends StatelessWidget {
  const _ViewChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? palette.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? palette.accent : palette.rule,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: selected ? palette.accent : palette.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.marked = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? palette.accentSoft : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: selected ? palette.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? palette.ink : palette.inkMuted,
                ),
              ),
            ),
            if (marked)
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: palette.accent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
