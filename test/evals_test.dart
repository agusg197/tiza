import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiza/evals/expected_note.dart';
import 'package:tiza/evals/fixture.dart';
import 'package:tiza/evals/metrics.dart';
import 'package:tiza/llm/structured_note.dart';

void main() {
  group('parseExpectedMarkdown', () {
    test('lee título, secciones con depth y action items con responsable', () {
      final note = parseExpectedMarkdown('''
# Sprint planning

## Objetivos

- cerrar el checkout
- migrar la base

### Detalle

- sub

## Action items

- Ana: revisar metricas
- hablar con legales
''');

      expect(note.title, 'Sprint planning');
      expect(note.sections.map((s) => s.heading), ['Objetivos', 'Detalle']);
      expect(note.sections[0].depth, 0);
      expect(note.sections[1].depth, 1);
      expect(note.actionItems[0].owner, 'Ana');
      expect(note.actionItems[0].text, 'revisar metricas');
      expect(note.actionItems[1].owner, isNull);
    });

    test('sobrevive el round-trip contra renderNoteMarkdown', () {
      // Es la garantía de que las dos puntas hablan el mismo idioma: si alguien
      // cambia el render y se olvida del parser, esto falla.
      const original = StructuredNote(
        title: 'T',
        sections: [
          NoteSection(heading: 'A', depth: 0, bullets: ['uno', 'dos']),
          NoteSection(heading: 'B', depth: 1, bullets: ['tres']),
        ],
        actionItems: [
          ActionItem(text: 'con dueño', owner: 'Ana'),
          ActionItem(text: 'sin dueño'),
        ],
      );

      final round = parseExpectedMarkdown(renderNoteMarkdown(original));

      expect(round.title, original.title);
      expect(
        round.sections.map((s) => '${s.heading}/${s.depth}/${s.bullets.join(",")}'),
        original.sections.map((s) => '${s.heading}/${s.depth}/${s.bullets.join(",")}'),
      );
      expect(
        round.actionItems.map((a) => '${a.owner}:${a.text}'),
        original.actionItems.map((a) => '${a.owner}:${a.text}'),
      );
    });

    test('ignora los bloques de comentario', () {
      // La plantilla que exporta la app trae `# Título` y `- bullet` de ejemplo
      // dentro de un comentario. Sin saltearlos, un expected.md sin completar
      // parecería tener contenido.
      final note = parseExpectedMarkdown('''
<!--
  # Título de ejemplo
  - bullet de ejemplo
-->

# El de verdad
''');

      expect(note.title, 'El de verdad');
      expect(note.sections, isEmpty);
    });

    test('no confunde una oración con dos puntos con un responsable', () {
      final note = parseExpectedMarkdown('''
## Action items

- avisar al proveedor que el contrato vence: no responde desde marzo
''');

      expect(note.actionItems.single.owner, isNull);
    });
  });

  group('normalizeForMatch', () {
    test('saca acentos, mayúsculas y puntuación', () {
      // Sacar los acentos es deliberado: el OCR los pierde y al modelo se le
      // prohíbe corregir lo que leyó el OCR, así que penalizarlo acá mediría el
      // OCR y no la estructuración.
      expect(normalizeForMatch('Revisar MÉTRICAS.'), 'revisar metricas');
      expect(normalizeForMatch('  hablar   con  legales '), 'hablar con legales');
      expect(normalizeForMatch('Año: ñandú'), 'ano nandu');
    });
  });

  group('compareTexts', () {
    test('cuenta lo que falta y lo que sobra', () {
      final score = compareTexts(
        ['uno', 'dos', 'tres'],
        ['dos', 'UNO', 'cuatro'],
      );

      expect(score.matched, 2);
      expect(score.missing, ['tres']);
      expect(score.spurious, ['cuatro']);
      expect(score.recall, closeTo(2 / 3, 1e-9));
      expect(score.precision, closeTo(2 / 3, 1e-9));
    });

    test('no cuenta dos veces el mismo acierto con duplicados', () {
      final score = compareTexts(['uno', 'uno'], ['uno']);
      expect(score.matched, 1);
      expect(score.missing, ['uno']);
    });

    test('esperar nada y no devolver nada es acierto perfecto', () {
      final score = compareTexts(const [], const []);
      expect(score.precision, 1);
      expect(score.recall, 1);
    });

    test('esperar nada y devolver algo es precisión cero', () {
      final score = compareTexts(const [], ['inventado']);
      expect(score.precision, 0);
      expect(score.spurious, ['inventado']);
    });
  });

  group('scoreNote', () {
    const expected = StructuredNote(
      title: 'Sprint planning',
      sections: [
        NoteSection(heading: 'Objetivos', bullets: ['uno', 'dos']),
      ],
      actionItems: [
        ActionItem(text: 'revisar metricas', owner: 'Ana'),
        ActionItem(text: 'deploy', owner: 'Beto'),
      ],
    );

    test('puntúa una respuesta perfecta', () {
      final score = scoreNote(expected: expected, actual: expected);

      expect(score.titleMatched, isTrue);
      expect(score.bullets.f1, 1);
      expect(score.ownerAccuracy, 1);
    });

    test('los bullets se comparan aplanados, sin exigir la misma sección', () {
      // Penalizar dos veces el mismo error —una por el bullet y otra por la
      // sección— haría que los números no se puedan leer.
      const movidos = StructuredNote(
        title: 'Sprint planning',
        sections: [
          NoteSection(heading: 'Otra', bullets: ['uno']),
          NoteSection(heading: 'Y otra', bullets: ['dos']),
        ],
        actionItems: [
          ActionItem(text: 'revisar metricas', owner: 'Ana'),
          ActionItem(text: 'deploy', owner: 'Beto'),
        ],
      );

      expect(scoreNote(expected: expected, actual: movidos).bullets.f1, 1);
    });

    test('un action item bien detectado con el dueño equivocado se distingue', () {
      const duenoMal = StructuredNote(
        title: 'Sprint planning',
        sections: [
          NoteSection(heading: 'Objetivos', bullets: ['uno', 'dos']),
        ],
        actionItems: [
          ActionItem(text: 'revisar metricas', owner: 'Beto'),
          ActionItem(text: 'deploy', owner: 'Beto'),
        ],
      );

      final score = scoreNote(expected: expected, actual: duenoMal);
      expect(score.actionItems.f1, 1);
      expect(score.ownerAccuracy, 0.5);
    });

    test('no regala el acierto de título cuando no había título esperado', () {
      const sinTitulo = StructuredNote(
        sections: [NoteSection(heading: 'H', bullets: ['a'])],
      );
      final score = scoreNote(expected: sinTitulo, actual: sinTitulo);

      expect(score.titleExpected, isFalse);
      expect(score.titleMatched, isFalse);
    });
  });

  group('scoreReadingOrder', () {
    const expected = StructuredNote(
      title: 'Sprint planning',
      sections: [
        NoteSection(heading: 'Objetivos', bullets: ['uno', 'dos']),
      ],
      actionItems: [ActionItem(text: 'revisar', owner: 'Ana')],
    );

    test('un orden que respeta los bloques hace los saltos mínimos', () {
      final score = scoreReadingOrder(
        expected: expected,
        orderedTexts: [
          'Sprint planning',
          'Objetivos',
          'uno',
          'dos',
          'Ana: revisar',
        ],
      );

      expect(score.groups, 3);
      expect(score.ideal, 2);
      expect(score.switches, 2);
      expect(score.perfect, isTrue);
    });

    test('intercalar bloques se paga en saltos de más', () {
      final score = scoreReadingOrder(
        expected: expected,
        orderedTexts: ['Sprint planning', 'uno', 'Ana: revisar', 'dos'],
      );

      // título → bullet → action → bullet: cuatro bloques recorridos en tres
      // saltos cuando alcanzaban dos.
      expect(score.switches, 3);
      expect(score.extra, 1);
      expect(score.perfect, isFalse);
    });

    test('reconoce el action item con el responsable adelante', () {
      // Así es como aparece el renglón en el pizarrón, y si no se reconociera
      // contaría como no mapeado y el conteo de saltos quedaría mal.
      final score = scoreReadingOrder(
        expected: expected,
        orderedTexts: ['Ana: revisar'],
      );
      expect(score.mapped, 1);
      expect(score.unmapped, 0);
    });

    test('los renglones que no están en el golden set no cuentan saltos', () {
      final score = scoreReadingOrder(
        expected: expected,
        orderedTexts: ['Objetivos', 'basura del OCR', 'uno'],
      );

      expect(score.unmapped, 1);
      expect(score.switches, 0);
    });
  });

  group('loadFixtures', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('tiza-fixtures'));
    tearDown(() => root.deleteSync(recursive: true));

    void write(String id, {String? ocr, String? expected}) {
      final folder = Directory('${root.path}/$id')..createSync();
      if (ocr != null) File('${folder.path}/ocr.json').writeAsStringSync(ocr);
      if (expected != null) {
        File('${folder.path}/expected.md').writeAsStringSync(expected);
      }
    }

    const ocrJson = '{"imageWidth":100,"imageHeight":100,"blocks":[]}';

    test('saltea y reporta los casos incompletos en vez de ignorarlos', () {
      // Un golden set que dice tener 20 casos y corre 14 en silencio produce
      // números que no significan nada.
      write('sin-ocr', expected: '# T');
      write('sin-expected', ocr: ocrJson);
      write('plantilla-sin-completar', ocr: ocrJson, expected: '<!-- vacío -->');
      write('ocr-roto', ocr: 'no soy json', expected: '# T');
      write('bueno', ocr: ocrJson, expected: '# T\n\n- a');

      final set = loadFixtures(root);

      expect(set.fixtures.map((f) => f.id), ['bueno']);
      expect(set.skipped.keys, containsAll([
        'sin-ocr',
        'sin-expected',
        'plantilla-sin-completar',
        'ocr-roto',
      ]));
      expect(set.skipped['plantilla-sin-completar'], contains('sin completar'));
    });

    test('un directorio que no existe se reporta, no explota', () {
      final set = loadFixtures(Directory('${root.path}/no-existe'));
      expect(set.fixtures, isEmpty);
      expect(set.skipped, isNotEmpty);
    });
  });
}
