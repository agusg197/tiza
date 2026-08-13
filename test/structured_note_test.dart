import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiza/llm/fake_llm_client.dart';
import 'package:tiza/llm/gemini_client.dart';
import 'package:tiza/llm/llm_client.dart';
import 'package:tiza/llm/model_option.dart';
import 'package:tiza/llm/note_prompt.dart';
import 'package:tiza/llm/note_schema.dart';
import 'package:tiza/llm/structured_note.dart';

/// El paso 5 completo, testeado sin red y sin key: el schema, el parseo estricto y
/// el render a markdown. Es donde está la decisión que más importa del paso —
/// descartar entradas inválidas y contarlas, en vez de tirar toda la respuesta o
/// aceptarla en silencio.
void main() {
  group('kNoteResponseSchema', () {
    /// Recorre el schema juntando todos los valores de `type`.
    List<String> collectTypes(Object? node) {
      if (node is Map) {
        return [
          if (node['type'] is String) node['type'] as String,
          for (final value in node.values) ...collectTypes(value),
        ];
      }
      if (node is List) {
        return [for (final item in node) ...collectTypes(item)];
      }
      return const [];
    }

    test('todos los tipos van en mayúsculas', () {
      // No es un detalle de estilo: el `type` de Gemini es un enum de proto, y en
      // minúsculas la API devuelve 400. Un test barato contra un error caro.
      const allowed = {'STRING', 'OBJECT', 'ARRAY', 'INTEGER', 'NUMBER', 'BOOLEAN'};
      final types = collectTypes(kNoteResponseSchema);

      expect(types, isNotEmpty);
      for (final type in types) {
        expect(allowed, contains(type), reason: '"$type" no es un tipo válido');
      }
    });

    test('cada campo en required existe entre las properties', () {
      void check(Map<String, dynamic> node) {
        final properties = node['properties'] as Map<String, dynamic>?;
        final required = node['required'] as List?;
        if (properties != null && required != null) {
          for (final name in required) {
            expect(
              properties.keys,
              contains(name),
              reason: 'required declara "$name" pero no está en properties',
            );
          }
        }
        for (final value in node.values) {
          if (value is Map<String, dynamic>) check(value);
        }
      }

      check(kNoteResponseSchema);
    });

    test('el schema se mantiene chato: no anida objetos más de dos niveles', () {
      // La especificación lo pide así, textual: "cuanto más anidado el schema, más
      // se equivoca el modelo".
      int depthOfObjects(Object? node) {
        if (node is Map) {
          final here = node['type'] == 'OBJECT' ? 1 : 0;
          var deepest = 0;
          for (final value in node.values) {
            final child = depthOfObjects(value);
            if (child > deepest) deepest = child;
          }
          return here + deepest;
        }
        if (node is List) {
          var deepest = 0;
          for (final item in node) {
            final child = depthOfObjects(item);
            if (child > deepest) deepest = child;
          }
          return deepest;
        }
        return 0;
      }

      expect(depthOfObjects(kNoteResponseSchema), lessThanOrEqualTo(2));
    });
  });

  group('parseStructuredNote', () {
    test('lee una respuesta bien formada sin advertencias', () {
      final result = parseStructuredNote('''
      {
        "title": "Sprint planning",
        "sections": [
          {"heading": "Objetivos", "depth": 0, "bullets": ["cerrar el checkout"]}
        ],
        "actionItems": [{"text": "revisar metricas", "owner": "Ana"}]
      }''');

      expect(result.warnings, isEmpty);
      expect(result.note.title, 'Sprint planning');
      expect(result.note.sections.single.heading, 'Objetivos');
      expect(result.note.sections.single.bullets, ['cerrar el checkout']);
      expect(result.note.actionItems.single.owner, 'Ana');
      expect(result.note.actionItems.single.text, 'revisar metricas');
    });

    test('un título vacío o ausente queda en null, sin advertir', () {
      expect(parseStructuredNote('{"title": null}').note.title, isNull);
      expect(parseStructuredNote('{"title": "   "}').note.title, isNull);
      expect(parseStructuredNote('{}').warnings, isEmpty);
    });

    test('un título que no es texto se descarta y se advierte', () {
      final result = parseStructuredNote('{"title": 42}');
      expect(result.note.title, isNull);
      expect(result.warnings, hasLength(1));
    });

    test('descarta bullets vacíos y dice cuántos', () {
      final result = parseStructuredNote('''
      {
        "sections": [
          {"heading": "H", "depth": 0, "bullets": ["uno", "", "  ", 7]}
        ]
      }''');

      expect(result.note.sections.single.bullets, ['uno']);
      expect(
        result.warnings.single,
        'Se descartaron 3 bullets vacíos o mal tipados.',
      );
    });

    test('una sección sin encabezado pero con bullets salva el contenido', () {
      // Tirar la sección entera perdería texto que el OCR sí leyó bien.
      final result = parseStructuredNote('''
      {
        "sections": [{"depth": 0, "bullets": ["esto se salva"]}]
      }''');

      expect(result.note.sections.single.heading, isEmpty);
      expect(result.note.sections.single.bullets, ['esto se salva']);
      expect(result.warnings.single, contains('sin encabezado'));
    });

    test('una sección sin encabezado y sin bullets se descarta', () {
      final result = parseStructuredNote('''
      {
        "sections": [{"depth": 0, "bullets": []}, {"heading": "H", "bullets": ["a"]}]
      }''');

      expect(result.note.sections, hasLength(1));
      expect(result.warnings.single, 'Se descartó 1 sección sin contenido usable.');
    });

    test('recorta depth en vez de rechazar la sección', () {
      final result = parseStructuredNote('''
      {
        "sections": [{"heading": "H", "depth": 9, "bullets": ["a"]}]
      }''');

      expect(result.note.sections.single.depth, 3);
      expect(result.warnings, isEmpty);
    });

    test('un depth que no es entero se asume 0 y se advierte', () {
      final result = parseStructuredNote('''
      {
        "sections": [{"heading": "H", "depth": "cero", "bullets": ["a"]}]
      }''');

      expect(result.note.sections.single.depth, 0);
      expect(result.warnings.single, contains('depth'));
    });

    test('descarta action items sin texto y normaliza el owner vacío', () {
      final result = parseStructuredNote('''
      {
        "actionItems": [
          {"text": "con dueño", "owner": "Ana"},
          {"text": "sin dueño", "owner": "  "},
          {"text": "", "owner": "Beto"},
          {"owner": "Cami"}
        ]
      }''');

      expect(result.note.actionItems, hasLength(2));
      expect(result.note.actionItems[1].owner, isNull);
      expect(result.warnings.single, 'Se descartaron 2 action items sin texto.');
    });

    test('sections o actionItems del tipo equivocado no tiran toda la nota', () {
      final result = parseStructuredNote('''
      {"title": "Igual sirve", "sections": "no soy lista", "actionItems": 3}''');

      expect(result.note.title, 'Igual sirve');
      expect(result.note.sections, isEmpty);
      expect(result.warnings, hasLength(2));
    });

    test('JSON malformado sí es fatal: no hay nada que recuperar', () {
      expect(
        () => parseStructuredNote('{"sections": ['),
        throwsA(
          isA<LlmException>()
              .having((e) => e.failure, 'failure', LlmFailure.badResponse),
        ),
      );
    });

    test('JSON válido que no es un objeto también es fatal', () {
      expect(
        () => parseStructuredNote('["no", "soy", "un", "objeto"]'),
        throwsA(isA<LlmException>()),
      );
    });
  });

  group('renderNoteMarkdown', () {
    test('arma el markdown completo, determinista', () {
      const note = StructuredNote(
        title: 'Sprint planning',
        sections: [
          NoteSection(
            heading: 'Objetivos',
            depth: 0,
            bullets: ['cerrar el checkout', 'migrar la base'],
          ),
          NoteSection(heading: 'Detalle', depth: 1, bullets: ['sub']),
        ],
        actionItems: [
          ActionItem(text: 'revisar metricas', owner: 'Ana'),
          ActionItem(text: 'hablar con legales'),
        ],
      );

      expect(renderNoteMarkdown(note), '''
# Sprint planning

## Objetivos

- cerrar el checkout
- migrar la base

### Detalle

- sub

## Action items

- Ana: revisar metricas
- hablar con legales''');
    });

    test('sin título no deja una línea en blanco al principio', () {
      const note = StructuredNote(
        sections: [NoteSection(heading: 'Solo', bullets: ['a'])],
      );
      expect(renderNoteMarkdown(note), '## Solo\n\n- a');
    });

    test('omite el encabezado de action items cuando no hay ninguno', () {
      const note = StructuredNote(
        sections: [NoteSection(heading: 'H', bullets: ['a'])],
      );
      expect(renderNoteMarkdown(note), isNot(contains('Action items')));
    });

    test('una sección salvada sin encabezado no emite un heading vacío', () {
      const note = StructuredNote(
        sections: [NoteSection(heading: '', bullets: ['huérfano'])],
      );
      expect(renderNoteMarkdown(note), '- huérfano');
    });

    test('una nota vacía devuelve string vacío, no basura', () {
      expect(renderNoteMarkdown(const StructuredNote()), isEmpty);
    });
  });

  group('buildStructuredReply', () {
    String envelope(String jsonText) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonText},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
      'usageMetadata': {'promptTokenCount': 500, 'candidatesTokenCount': 200},
      'modelVersion': 'gemini-2.5-flash',
    });

    test('convierte la respuesta de la API en nota, markdown y tokens', () {
      final reply = buildStructuredReply(
        envelope(
          '{"title":"T","sections":[{"heading":"H","depth":0,"bullets":["a"]}],'
          '"actionItems":[]}',
        ),
        const Duration(milliseconds: 900),
      );

      expect(reply.structured, isTrue);
      expect(reply.note!.title, 'T');
      // El markdown no lo escribió el modelo: lo armó renderNoteMarkdown sobre
      // datos ya validados. Esa es la diferencia central del paso 5.
      expect(reply.markdown, '# T\n\n## H\n\n- a');
      expect(reply.rawJson, contains('"heading":"H"'));
      expect(reply.promptTokens, 500);
      expect(reply.warnings, isEmpty);
    });

    test('propaga las advertencias del parseo estricto', () {
      final reply = buildStructuredReply(
        envelope('{"sections":[{"heading":"H","depth":0,"bullets":["a",""]}]}'),
        Duration.zero,
      );

      expect(reply.warnings, hasLength(1));
      expect(reply.note!.bulletCount, 1);
    });
  });

  group('prompt con schema', () {
    test('no repite instrucciones de formato: eso lo garantiza el schema', () {
      final system = buildStructuredSystemInstruction();

      // Con responseSchema puesto, pedir "sólo markdown" o "sin bloque de código"
      // sería gastar tokens en cada llamada para algo que impone la API.
      expect(system, isNot(contains('markdown')));
      expect(system, isNot(contains('bloque de código')));
      // Lo que queda son reglas de contenido, que ningún schema puede imponer.
      expect(system, contains('No inventes contenido'));
      expect(system, contains('no lo deduzcas'));
    });
  });

  group('FakeLlmClient.structureNote', () {
    test('devuelve una nota y ejercita el camino de validación estricta', () async {
      final reply = await const FakeLlmClient(latency: Duration.zero)
          .structureNote(serializedOcr: 'texto', model: kDefaultModel);

      expect(reply.structured, isTrue);
      expect(reply.note!.title, 'Sprint planning');
      expect(reply.note!.actionItems, hasLength(3));
      // La respuesta simulada trae a propósito un bullet vacío y un action item
      // sin texto, para que el estado con advertencias se pueda ver en pantalla.
      expect(reply.warnings, hasLength(2));
      expect(reply.markdown, contains('- Ana: revisar metricas'));
    });
  });
}
