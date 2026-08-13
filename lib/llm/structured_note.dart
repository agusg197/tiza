import 'dart:convert';
import 'dart:math' as math;

import 'llm_client.dart';

/// La nota estructurada: lo que devuelve el modelo cuando se le impone un schema.
///
/// Es Dart puro, igual que [OcrResult]: el parseo estricto y el render a markdown
/// son funciones que se testean en la máquina, sin red y sin key.
class StructuredNote {
  const StructuredNote({
    this.title,
    this.sections = const [],
    this.actionItems = const [],
  });

  final String? title;
  final List<NoteSection> sections;
  final List<ActionItem> actionItems;

  bool get isEmpty =>
      title == null && sections.isEmpty && actionItems.isEmpty;

  int get bulletCount =>
      sections.fold(0, (total, section) => total + section.bullets.length);
}

class NoteSection {
  const NoteSection({
    required this.heading,
    this.bullets = const [],
    this.depth = 0,
  });

  final String heading;
  final List<String> bullets;

  /// Nivel de anidamiento de la sección. Se limita a 0–3 al parsear: la
  /// especificación pide mantener el schema chato, y un modelo al que se le deja
  /// anidar libremente devuelve jerarquías que no estaban en el pizarrón.
  final int depth;
}

class ActionItem {
  const ActionItem({required this.text, this.owner});

  final String text;
  final String? owner;
}

/// Resultado de parsear la respuesta del modelo.
///
/// [warnings] no es un detalle: es la medida de cuánto se equivocó el modelo
/// contra el schema. En el paso 7 esa cuenta va a la tabla, porque un modelo que
/// acierta el contenido pero devuelve tres entradas inválidas por foto no es
/// equivalente a uno que devuelve cero.
class NoteParseResult {
  const NoteParseResult({required this.note, required this.warnings});

  final StructuredNote note;
  final List<String> warnings;
}

/// Parsea la respuesta del modelo con validación estricta y recuperación parcial.
///
/// La decisión de diseño está acá: ante una entrada inválida **se descarta esa
/// entrada y se sigue**, en vez de tirar toda la respuesta. Descartar todo por un
/// bullet vacío desperdicia una llamada que salió bien en un 95%; ignorar el
/// problema en silencio hace que las evals midan de más. Descartar y contar es lo
/// único que cumple las dos cosas.
///
/// El JSON malformado sí es fatal: ahí no hay nada que recuperar. Y no se
/// reintenta solo a propósito — un reintento automático arregla la pantalla pero
/// esconde la tasa de fallo, que es justo el número que este proyecto quiere
/// medir. El usuario tiene el botón para volver a preguntar.
NoteParseResult parseStructuredNote(String jsonText) {
  final Object? decoded;
  try {
    decoded = jsonDecode(jsonText);
  } catch (_) {
    throw LlmException(
      LlmFailure.badResponse,
      'El modelo devolvió algo que no es JSON, aun con el schema puesto.',
      // El texto que llegó va en el detalle. Es lo único con lo que se puede
      // entender por qué falló, y antes se descartaba.
      detail: _snippet(jsonText),
    );
  }

  if (decoded is! Map<String, dynamic>) {
    throw LlmException(
      LlmFailure.badResponse,
      'El modelo devolvió JSON válido pero no un objeto.',
      detail: _snippet(jsonText),
    );
  }

  final warnings = <String>[];

  return NoteParseResult(
    note: StructuredNote(
      title: _readTitle(decoded['title'], warnings),
      sections: _readSections(decoded['sections'], warnings),
      actionItems: _readActionItems(decoded['actionItems'], warnings),
    ),
    warnings: warnings,
  );
}

/// Un recorte de la respuesta para el detalle del error. Se corta porque un
/// modelo que se descarrila puede devolver miles de caracteres, y eso no cabe en
/// una nota de error ni ayuda a entender nada.
String _snippet(String text, [int max = 300]) {
  final flat = text.trim();
  return flat.length <= max ? flat : '${flat.substring(0, max)}…';
}

/// "Se descartó 1 bullet vacío" y no "se descartaron 1 bullets vacíos".
///
/// Es una tontería y aparece en pantalla, así que se arregla en un lugar en vez de
/// en cada mensaje.
String _dropped(int count, String singular, String plural) =>
    count == 1 ? 'Se descartó 1 $singular.' : 'Se descartaron $count $plural.';

String? _readTitle(Object? raw, List<String> warnings) {
  if (raw == null) return null;
  if (raw is! String) {
    warnings.add('El título no era texto y se descartó.');
    return null;
  }
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<NoteSection> _readSections(Object? raw, List<String> warnings) {
  if (raw == null) return const [];
  if (raw is! List) {
    warnings.add('"sections" no era una lista y se descartó.');
    return const [];
  }

  final sections = <NoteSection>[];
  var dropped = 0;

  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) {
      dropped++;
      continue;
    }

    final heading = entry['heading'];
    final bullets = _readBullets(entry['bullets'], warnings);

    if (heading is! String || heading.trim().isEmpty) {
      // Sin encabezado pero con bullets, el contenido se puede salvar: se cuelga
      // de una sección sin título en vez de perderse.
      if (bullets.isEmpty) {
        dropped++;
        continue;
      }
      warnings.add('Una sección vino sin encabezado; se conservaron sus bullets.');
      sections.add(NoteSection(heading: '', bullets: bullets, depth: 0));
      continue;
    }

    sections.add(
      NoteSection(
        heading: heading.trim(),
        bullets: bullets,
        depth: _readDepth(entry['depth'], warnings),
      ),
    );
  }

  if (dropped > 0) {
    warnings.add(
      _dropped(
        dropped,
        'sección sin contenido usable',
        'secciones sin contenido usable',
      ),
    );
  }
  return sections;
}

List<String> _readBullets(Object? raw, List<String> warnings) {
  if (raw == null) return const [];
  if (raw is! List) {
    warnings.add('"bullets" no era una lista y se descartó.');
    return const [];
  }

  final bullets = <String>[];
  var dropped = 0;

  for (final entry in raw) {
    if (entry is String && entry.trim().isNotEmpty) {
      bullets.add(entry.trim());
    } else {
      dropped++;
    }
  }

  if (dropped > 0) {
    warnings.add(
      _dropped(
        dropped,
        'bullet vacío o mal tipado',
        'bullets vacíos o mal tipados',
      ),
    );
  }
  return bullets;
}

int _readDepth(Object? raw, List<String> warnings) {
  if (raw == null) return 0;
  if (raw is! int) {
    warnings.add('Un "depth" no era entero; se asumió 0.');
    return 0;
  }
  // Se recorta en vez de rechazar: el schema pide chato, y un depth de 7 es un
  // exceso del modelo, no una respuesta inservible.
  return raw.clamp(0, 3);
}

List<ActionItem> _readActionItems(Object? raw, List<String> warnings) {
  if (raw == null) return const [];
  if (raw is! List) {
    warnings.add('"actionItems" no era una lista y se descartó.');
    return const [];
  }

  final items = <ActionItem>[];
  var dropped = 0;

  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) {
      dropped++;
      continue;
    }

    final text = entry['text'];
    if (text is! String || text.trim().isEmpty) {
      dropped++;
      continue;
    }

    final owner = entry['owner'];
    items.add(
      ActionItem(
        text: text.trim(),
        owner: owner is String && owner.trim().isNotEmpty ? owner.trim() : null,
      ),
    );
  }

  if (dropped > 0) {
    warnings.add(
      _dropped(dropped, 'action item sin texto', 'action items sin texto'),
    );
  }
  return items;
}

/// Convierte la nota en markdown. Función pura y determinista.
///
/// Que sea pura importa por dos razones: se testea sin LLM ni red, y es lo que el
/// runner del paso 7 va a comparar contra el markdown escrito a mano del golden
/// set. Si el render fuera parte del widget, no habría con qué diferenciar.
///
/// Reglas: `#` queda reservado para el título; el encabezado de una sección
/// arranca en `##` y baja un nivel por cada unidad de `depth`.
String renderNoteMarkdown(StructuredNote note) {
  final lines = <String>[];

  if (note.title != null) {
    lines..add('# ${note.title}')..add('');
  }

  for (final section in note.sections) {
    if (section.heading.isNotEmpty) {
      final hashes = '#' * math.min(6, 2 + section.depth);
      lines..add('$hashes ${section.heading}')..add('');
    }
    for (final bullet in section.bullets) {
      lines.add('- $bullet');
    }
    if (section.bullets.isNotEmpty) lines.add('');
  }

  if (note.actionItems.isNotEmpty) {
    lines..add('## Action items')..add('');
    for (final item in note.actionItems) {
      lines.add(item.owner == null ? '- ${item.text}' : '- ${item.owner}: ${item.text}');
    }
  }

  // Una sola pasada final para no dejar líneas en blanco al final ni dos
  // seguidas: el markdown tiene que ser estable carácter a carácter para poder
  // diferenciarlo contra el golden set.
  final joined = lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return joined.trim();
}
