import 'package:flutter/material.dart';

import '../../theme/tiza_theme.dart';

/// El markdown que devolvió el modelo, **sin renderizar**.
///
/// Es deliberado. El paso 4 de la especificación existe para ver qué devuelve el
/// modelo antes de restringirlo con un schema, y renderizarlo esconde justo lo que
/// se está mirando: un encabezado de nivel equivocado, un bullet que quedó suelto,
/// un bloque de código que no se pidió. Todo eso desaparece si se muestra bonito.
///
/// Lo único que se hace es marcar la sintaxis en terracota —los `#` y los
/// guiones— para que la estructura se lea de un vistazo sin dejar de ver los
/// caracteres reales. El render llega en el paso 5, sobre el objeto ya parseado.
class MarkdownRawView extends StatelessWidget {
  const MarkdownRawView({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;

    const base = TextStyle(fontFamily: kMono, fontSize: 12.5, height: 1.55);
    final syntax = base.copyWith(color: palette.accent);
    final body = base.copyWith(color: palette.ink);
    final heading = base.copyWith(color: palette.ink, fontWeight: FontWeight.w700);

    final lines = markdown.split('\n');
    final spans = <TextSpan>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final suffix = i == lines.length - 1 ? '' : '\n';
      final trimmed = line.trimLeft();
      final indent = line.substring(0, line.length - trimmed.length);

      if (trimmed.startsWith('#')) {
        final hashes = RegExp(r'^#+').firstMatch(trimmed)!.group(0)!;
        spans
          ..add(TextSpan(text: '$indent$hashes', style: syntax))
          ..add(TextSpan(
            text: '${trimmed.substring(hashes.length)}$suffix',
            style: heading,
          ));
        continue;
      }

      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        spans
          ..add(TextSpan(text: '$indent${trimmed[0]}', style: syntax))
          ..add(TextSpan(text: '${trimmed.substring(1)}$suffix', style: body));
        continue;
      }

      spans.add(TextSpan(text: '$line$suffix', style: body));
    }

    return SelectableText.rich(TextSpan(children: spans), style: base);
  }
}
