import 'dart:convert';
import 'dart:io';

import '../llm/structured_note.dart';
import '../ocr/models/ocr_result.dart';
import 'expected_note.dart';

/// Un caso del golden set: el OCR congelado de una foto y el markdown que
/// debería salir.
///
/// El fixture guarda **la salida del OCR, no la imagen**. Es lo que hace que las
/// evals corran en la máquina en milisegundos, sin emulador y sin MLKit, y que dos
/// corridas de la misma configuración den exactamente lo mismo. La imagen se
/// guarda al lado sólo para poder mirarla cuando un número no cierra.
class EvalFixture {
  const EvalFixture({
    required this.id,
    required this.ocr,
    required this.expected,
    required this.expectedMarkdown,
  });

  final String id;
  final OcrResult ocr;
  final StructuredNote expected;
  final String expectedMarkdown;
}

/// Lo que se encontró al cargar el golden set, incluido lo que se salteó.
class FixtureSet {
  const FixtureSet({required this.fixtures, required this.skipped});

  final List<EvalFixture> fixtures;

  /// Carpetas que no se pudieron usar, con el motivo. Se reportan en vez de
  /// ignorarse: un golden set que dice tener 20 casos y corre 14 en silencio
  /// produce números que no significan nada.
  final Map<String, String> skipped;
}

/// Carga los fixtures de un directorio.
///
/// Cada caso es una subcarpeta con `ocr.json` y `expected.md`.
FixtureSet loadFixtures(Directory root) {
  if (!root.existsSync()) {
    return FixtureSet(
      fixtures: const [],
      skipped: {root.path: 'el directorio no existe'},
    );
  }

  final fixtures = <EvalFixture>[];
  final skipped = <String, String>{};

  final folders = root.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final folder in folders) {
    final id = folder.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final ocrFile = File('${folder.path}${Platform.pathSeparator}ocr.json');
    final expectedFile = File('${folder.path}${Platform.pathSeparator}expected.md');

    if (!ocrFile.existsSync()) {
      skipped[id] = 'falta ocr.json';
      continue;
    }
    if (!expectedFile.existsSync()) {
      skipped[id] = 'falta expected.md';
      continue;
    }

    final markdown = expectedFile.readAsStringSync();
    // El export desde la app deja un expected.md con una plantilla en comentarios.
    // Si nadie lo completó, el caso no sirve y decirlo es mejor que puntuar contra
    // una nota vacía y reportar un 0% que parece un fallo del modelo.
    final expected = parseExpectedMarkdown(markdown);
    if (expected.title == null &&
        expected.sections.isEmpty &&
        expected.actionItems.isEmpty) {
      skipped[id] = 'expected.md está vacío o sin completar';
      continue;
    }

    final OcrResult ocr;
    try {
      ocr = OcrResult.fromJson(
        jsonDecode(ocrFile.readAsStringSync()) as Map<String, dynamic>,
      );
    } catch (error) {
      skipped[id] = 'ocr.json no se pudo leer: $error';
      continue;
    }

    fixtures.add(
      EvalFixture(
        id: id,
        ocr: ocr,
        expected: expected,
        expectedMarkdown: markdown,
      ),
    );
  }

  return FixtureSet(fixtures: fixtures, skipped: skipped);
}
