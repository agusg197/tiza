import 'package:flutter/material.dart';

import '../../theme/tiza_theme.dart';

/// El texto serializado, con tres niveles de tinta.
///
/// Es literalmente el string que se le va a mandar al modelo, pero mostrarlo como
/// un bloque plano lo vuelve ilegible: los corchetes de coordenadas y el texto
/// reconocido compiten. Acá la leyenda queda apagada, las coordenadas van en
/// terracota y el texto en tinta plena, así se puede leer la estructura de un
/// vistazo. Sigue siendo seleccionable y lo que se copia es el texto crudo, sin
/// ningún agregado del formato visual.
class SerializationView extends StatelessWidget {
  const SerializationView({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;

    const base = TextStyle(fontFamily: kMono, fontSize: 12.5, height: 1.55);
    final legend = base.copyWith(color: palette.inkFaint);
    final coords = base.copyWith(color: palette.accent);
    final body = base.copyWith(color: palette.ink);

    final lines = text.split('\n');
    final spans = <TextSpan>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final suffix = i == lines.length - 1 ? '' : '\n';

      if (line.startsWith('#')) {
        spans.add(TextSpan(text: '$line$suffix', style: legend));
        continue;
      }

      // `[  5   8 100] Sprint planning` → el corchete en terracota, el resto en
      // tinta. El serializador de texto plano no tiene corchetes y cae al else.
      final close = line.indexOf(']');
      if (line.startsWith('[') && close > 0) {
        spans.add(TextSpan(text: line.substring(0, close + 1), style: coords));
        spans.add(TextSpan(text: '${line.substring(close + 1)}$suffix', style: body));
      } else {
        spans.add(TextSpan(text: '$line$suffix', style: body));
      }
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      style: base,
    );
  }
}
