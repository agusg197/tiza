import '../llm/structured_note.dart';

/// Lee el markdown escrito a mano del golden set y lo convierte en la misma
/// [StructuredNote] que produce el modelo.
///
/// Que las dos puntas terminen en el mismo tipo es lo que permite comparar sin
/// diferenciar texto: `renderNoteMarkdown` escribe, esto lee, y las métricas
/// trabajan sobre estructuras. Hay un test de ida y vuelta —render, parseo, misma
/// estructura— que es la garantía de que las dos funciones hablan el mismo idioma.
///
/// Reconoce el subconjunto de markdown que emite la app y nada más: `#` título,
/// `##`+ encabezados de sección, `-` bullets, y una sección "Action items" que
/// cambia el destino de los bullets. Un parser de markdown completo acá sería
/// resolver un problema que no tenemos.
StructuredNote parseExpectedMarkdown(String markdown) {
  String? title;
  final sections = <NoteSection>[];
  final actionItems = <ActionItem>[];

  var inActionItems = false;
  var inComment = false;
  String? heading;
  var depth = 0;
  var bullets = <String>[];

  void flushSection() {
    if (heading != null || bullets.isNotEmpty) {
      sections.add(
        NoteSection(heading: heading ?? '', bullets: bullets, depth: depth),
      );
    }
    heading = null;
    depth = 0;
    bullets = <String>[];
  }

  for (final raw in markdown.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    // Los bloques `<!-- -->` se saltean enteros. Hace falta de verdad: la
    // plantilla que exporta la app trae dentro de un comentario un ejemplo de
    // formato con `# Título` y `- bullet`, y sin esto un `expected.md` sin
    // completar parecería tener contenido y el runner lo puntuaría.
    if (inComment) {
      if (line.contains('-->')) inComment = false;
      continue;
    }
    if (line.startsWith('<!--')) {
      if (!line.contains('-->')) inComment = true;
      continue;
    }

    if (line.startsWith('#')) {
      final hashes = RegExp(r'^#+').firstMatch(line)!.group(0)!;
      final text = line.substring(hashes.length).trim();

      if (hashes.length == 1) {
        flushSection();
        inActionItems = false;
        title = text;
        continue;
      }

      // "Action items" en cualquier nivel y sin importar mayúsculas: el golden set
      // lo escribe una persona y no hay razón para ser estricto con eso.
      if (_isActionHeading(text)) {
        flushSection();
        inActionItems = true;
        continue;
      }

      flushSection();
      inActionItems = false;
      heading = text;
      depth = hashes.length - 2;
      continue;
    }

    if (line.startsWith('- ') || line.startsWith('* ')) {
      final text = line.substring(2).trim();
      if (text.isEmpty) continue;

      if (inActionItems) {
        actionItems.add(_parseActionItem(text));
      } else {
        bullets.add(text);
      }
      continue;
    }

    // Cualquier otra línea se ignora. El golden set puede tener notas al pie o
    // párrafos y no queremos que ensucien las métricas.
  }

  flushSection();

  return StructuredNote(
    title: title,
    sections: sections,
    actionItems: actionItems,
  );
}

bool _isActionHeading(String text) {
  final normalized = text.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), '').trim();
  return normalized == 'action items' || normalized == 'tareas';
}

/// `Ana: revisar métricas` → owner Ana. `revisar métricas` → sin owner.
///
/// Sólo se toma como responsable un prefijo corto: sin este límite, una tarea como
/// "avisar al proveedor: no responde" convertiría media oración en un nombre.
ActionItem _parseActionItem(String text) {
  final colon = text.indexOf(':');
  if (colon <= 0) return ActionItem(text: text);

  final candidate = text.substring(0, colon).trim();
  final rest = text.substring(colon + 1).trim();

  final looksLikeName =
      rest.isNotEmpty && candidate.length <= 30 && candidate.split(' ').length <= 3;

  return looksLikeName
      ? ActionItem(text: rest, owner: candidate)
      : ActionItem(text: text);
}
