// Corre el golden set y escribe la tabla de resultados.
//
//   $env:GEMINI_API_KEY = "..."
//   dart run tool/evals.dart --dry-run
//   dart run tool/evals.dart
//
// Es un script y no un test a propósito: gasta tokens contra una API real, y algo
// que cuesta dinero no tiene que poder dispararse por correr `flutter test`. Las
// métricas y el parseo, que son lo que puede tener bugs, sí están en tests.
//
// Ejes que se pueden mover (los tres a la vez arman la matriz):
//   --serializers plain,coords
//   --models flash-lite-3.5,flash-3.5,flash-3.6
//   --modes schema,freeMarkdown
//   --limit 3          sólo las primeras N fotos
//   --fixtures ruta    por defecto ./fixtures
//   --fake             usa la respuesta simulada: cero tokens y sin key
//   --show             imprime la serialización de cada caso y termina
//   --delay ms         pausa entre llamadas (4500 por defecto)
//
// `--fake` no es un juguete: es lo que permite verificar el harness completo
// —cargar fixtures, serializar, parsear, puntuar, imprimir la tabla— sin gastar
// nada. Los números que salen no dicen nada del modelo, dicen que la cañería está
// bien conectada.

import 'dart:io';

import 'package:tiza/evals/expected_note.dart';
import 'package:tiza/evals/fixture.dart';
import 'package:tiza/evals/metrics.dart';
import 'package:tiza/llm/fake_llm_client.dart';
import 'package:tiza/llm/gemini_client.dart';
import 'package:tiza/llm/llm_client.dart';
import 'package:tiza/llm/model_option.dart';
import 'package:tiza/serialization/layout_serializer.dart';

Future<void> main(List<String> arguments) async {
  final options = _parseArgs(arguments);

  // La key se lee del entorno y nunca se pasa por línea de comandos: en el
  // historial del shell quedaría en texto plano.
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  final dryRun = options.containsKey('dry-run');

  final root = Directory(options['fixtures'] ?? 'fixtures');
  final set = loadFixtures(root);

  if (set.skipped.isNotEmpty) {
    stdout.writeln('Casos salteados:');
    set.skipped.forEach((id, why) => stdout.writeln('  $id — $why'));
    stdout.writeln('');
  }

  if (set.fixtures.isEmpty) {
    stderr.writeln('No hay ningún caso usable en ${root.path}.');
    exitCode = 1;
    return;
  }

  var fixtures = set.fixtures;
  final limit = int.tryParse(options['limit'] ?? '');
  if (limit != null && limit < fixtures.length) {
    fixtures = fixtures.sublist(0, limit);
  }

  final serializers = _pickSerializers(options['serializers']);
  final models = _pickModels(options['models']);
  final modes = _pickModes(options['modes']);

  final calls = fixtures.length * serializers.length * models.length * modes.length;
  stdout.writeln(
    '${fixtures.length} fotos × ${serializers.length} serializadores × '
    '${models.length} modelos × ${modes.length} modos = $calls llamadas',
  );

  // La tabla de orden va antes y siempre: no cuesta nada, no necesita key, y
  // contesta sola si una idea de layout mejora o empeora el agrupamiento.
  _printOrderTable(fixtures, serializers);

  // Un número que mejora sin poder mirar qué cambió es un número en el que no se
  // puede confiar. `--show` imprime la serialización cruda de cada caso.
  if (options.containsKey('show')) {
    for (final serializer in serializers) {
      for (final fixture in fixtures) {
        stdout.writeln('--- ${serializer.id} · ${fixture.id} ---');
        stdout.writeln(serializer.serialize(fixture.ocr));
        stdout.writeln('');
      }
    }
    return;
  }

  if (dryRun) {
    stdout.writeln('--dry-run: no se llamó a la API.');
    return;
  }

  final fake = options.containsKey('fake');

  if (!fake && (apiKey == null || apiKey.trim().isEmpty)) {
    stderr.writeln(
      '\nFalta GEMINI_API_KEY en el entorno. En PowerShell:\n'
      r'  $env:GEMINI_API_KEY = "tu-key"'
      '\n\nO probá el harness sin gastar tokens con --fake.',
    );
    exitCode = 1;
    return;
  }

  if (fake) {
    stdout.writeln(
      'MODO --fake: respuesta simulada. Los números NO dicen nada del modelo.',
    );
  }

  // Sin pausa entre llamadas, el tier gratuito corta por límite de peticiones por
  // minuto: en la primera corrida de 30 llamadas fallaron 12 con 429. Con el fake no
  // hay a quién limitar, así que ahí la pausa es cero.
  final delay = fake
      ? Duration.zero
      : Duration(milliseconds: int.tryParse(options['delay'] ?? '') ?? 4500);

  if (!fake) {
    final estimado = Duration(milliseconds: calls * (delay.inMilliseconds + 1200));
    stdout.writeln(
      'pausa de ${delay.inMilliseconds} ms entre llamadas · '
      'estimado ~${estimado.inMinutes} min',
    );
  }

  final LlmClient client = fake
      ? const FakeLlmClient(latency: Duration(milliseconds: 30))
      : GeminiClient(apiKey: apiKey!);
  final rows = <_Row>[];

  for (final serializer in serializers) {
    for (final model in models) {
      for (final mode in modes) {
        stdout.write(
          '\n${serializer.id} · ${model.id} · ${mode.name} ',
        );
        final row = _Row(serializer: serializer.id, model: model.id, mode: mode.name);

        for (final fixture in fixtures) {
          final serialized = serializer.serialize(fixture.ocr);
          try {
            final reply = await _askWithRetry(
              client: client,
              model: model,
              mode: mode,
              serialized: serialized,
              delay: delay,
            );
            row.add(fixture, reply, serialized.length);
            stdout.write('.');
          } on LlmException catch (error) {
            row.failures.add('${fixture.id}: ${error.failure.name}');
            stdout.write('x');
          }
        }

        rows.add(row);
      }
    }
  }

  if (client is GeminiClient) client.close();
  stdout.writeln('\n');
  _printTable(rows, fixtures.length);
}

/// Acumula los resultados de una configuración sobre todas las fotos.
class _Row {
  _Row({required this.serializer, required this.model, required this.mode});

  final String serializer;
  final String model;
  final String mode;

  final List<String> failures = [];
  final List<NoteScore> scores = [];

  int titlesExpected = 0;
  int titlesMatched = 0;
  int bulletsExpected = 0;
  int bulletsActual = 0;
  int bulletsMatched = 0;
  int actionsExpected = 0;
  int actionsActual = 0;
  int actionsMatched = 0;
  int ownersExpected = 0;
  int ownersMatched = 0;
  int discarded = 0;
  int promptTokens = 0;
  int outputTokens = 0;
  int millis = 0;
  int inputChars = 0;

  void add(EvalFixture fixture, ModelReply reply, int serializedLength) {
    // En markdown libre no hay `note`, así que la respuesta se lee con el **mismo**
    // parser que el golden set. Que sea el mismo importa: uno más permisivo para
    // la respuesta que para lo esperado le daría al modo sin schema una ventaja
    // artificial.
    final actual = reply.note ?? parseExpectedMarkdown(reply.markdown);
    final score = scoreNote(expected: fixture.expected, actual: actual);

    scores.add(score);
    if (score.titleExpected) {
      titlesExpected++;
      if (score.titleMatched) titlesMatched++;
    }
    bulletsExpected += score.bullets.expected;
    bulletsActual += score.bullets.actual;
    bulletsMatched += score.bullets.matched;
    actionsExpected += score.actionItems.expected;
    actionsActual += score.actionItems.actual;
    actionsMatched += score.actionItems.matched;
    ownersExpected += score.ownersExpected;
    ownersMatched += score.ownersMatched;
    discarded += reply.warnings.length;
    promptTokens += reply.promptTokens ?? 0;
    outputTokens += reply.outputTokens ?? 0;
    millis += reply.elapsed.inMilliseconds;
    inputChars += serializedLength;
  }

  int get n => scores.length;

  String get titleCell =>
      titlesExpected == 0 ? '—' : '$titlesMatched/$titlesExpected';

  String _pr(int matched, int expected, int actual) {
    if (expected == 0 && actual == 0) return '—';
    final precision = actual == 0 ? 0.0 : matched / actual;
    final recall = expected == 0 ? 1.0 : matched / expected;
    return '${_pct(precision)} / ${_pct(recall)}';
  }

  String get bulletCell => _pr(bulletsMatched, bulletsExpected, bulletsActual);
  String get actionCell => _pr(actionsMatched, actionsExpected, actionsActual);
  String get ownerCell =>
      ownersExpected == 0 ? '—' : _pct(ownersMatched / ownersExpected);

  String get tokensCell => n == 0 ? '—' : '${promptTokens ~/ n}→${outputTokens ~/ n}';
  String get latencyCell => n == 0 ? '—' : '${millis ~/ n} ms';
  String get charsCell => n == 0 ? '—' : '${inputChars ~/ n}';
  String get failureCell => failures.isEmpty ? '—' : '${failures.length}';
}

/// Una llamada, con pausa previa y reintentos ante 429.
///
/// El tier gratuito limita por peticiones por minuto, así que un runner que dispara
/// todo seguido no puede terminar: en la primera corrida de 30 llamadas, 12 murieron
/// con `rateLimited`. Y una cuota agotada **no es un fallo del modelo** — dejarla
/// contar como fallo mezcla un problema de infraestructura con una medición de
/// calidad.
///
/// La espera del reintento es larga a propósito: el límite es por minuto, así que
/// reintentar a los dos segundos vuelve a chocar contra el mismo techo.
Future<ModelReply> _askWithRetry({
  required LlmClient client,
  required ModelOption model,
  required OutputMode mode,
  required String serialized,
  required Duration delay,
  int intentos = 3,
}) async {
  for (var intento = 1; ; intento++) {
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    try {
      return mode == OutputMode.schema
          ? await client.structureNote(serializedOcr: serialized, model: model)
          : await client.writeMarkdown(serializedOcr: serialized, model: model);
    } on LlmException catch (error) {
      final reintentable = error.failure == LlmFailure.rateLimited ||
          error.failure == LlmFailure.server;
      if (!reintentable || intento >= intentos) rethrow;

      final espera = Duration(seconds: 30 * intento);
      stdout.write('~${espera.inSeconds}s');
      await Future<void>.delayed(espera);
    }
  }
}

/// Orden de lectura por serializador. Sin API, sin tokens, sin key.
void _printOrderTable(List<EvalFixture> fixtures, List<LayoutSerializer> serializers) {
  stdout.writeln('\nOrden de lectura (gratis, sin llamar al modelo):\n');
  stdout.writeln(
    '| serializador | casos | saltos | ideal | de más | inversiones | perfectos |',
  );
  stdout.writeln('|---|---|---|---|---|---|---|');

  // Qué caso falla en cada serializador. Sin esto el total no se puede
  // interpretar: dos saltos de más pueden ser un límite conocido o un bug nuevo.
  final offenders = <String, List<String>>{};

  for (final serializer in serializers) {
    var switches = 0;
    var ideal = 0;
    var inversions = 0;
    var perfect = 0;

    for (final fixture in fixtures) {
      final score = scoreReadingOrder(
        expected: fixture.expected,
        orderedTexts: [
          for (final line in serializer.order(fixture.ocr)) line.text,
        ],
      );
      switches += score.switches;
      ideal += score.ideal;
      inversions += score.inversions;
      if (score.perfect) {
        perfect++;
      } else {
        offenders.putIfAbsent(serializer.id, () => []).add(
          '${fixture.id} (+${score.extra} saltos, ${score.inversions} inv.)',
        );
      }
    }

    stdout.writeln(
      '| ${serializer.id} | ${fixtures.length} | $switches | $ideal | '
      '${switches - ideal} | $inversions | $perfect/${fixtures.length} |',
    );
  }

  if (offenders.isNotEmpty) {
    stdout.writeln('\nCasos con saltos de más:');
    offenders.forEach((id, cases) {
      stdout.writeln('  $id: ${cases.join(', ')}');
    });
  }
  stdout.writeln('');
}

String _pct(double value) => '${(value * 100).round()}%';

void _printTable(List<_Row> rows, int total) {
  stdout.writeln(
    '| serializador | modelo | modo | n | título | bullets P/R | actions P/R | '
    'owners | descartes | tokens | latencia | car. entrada | fallos |',
  );
  stdout.writeln(
    '|---|---|---|---|---|---|---|---|---|---|---|---|---|',
  );
  for (final row in rows) {
    // La `n` se imprime como fracción y las filas incompletas van marcadas. Sin
    // esto la tabla invita a comparar un 100% sobre un caso contra un 88% sobre
    // cinco, que es exactamente la conclusión equivocada.
    final incompleta = row.n < total ? ' ⚠' : '';
    stdout.writeln(
      '| ${row.serializer} | ${row.model} | ${row.mode} | ${row.n}/$total$incompleta | '
      '${row.titleCell} | ${row.bulletCell} | ${row.actionCell} | '
      '${row.ownerCell} | ${row.discarded} | ${row.tokensCell} | '
      '${row.latencyCell} | ${row.charsCell} | ${row.failureCell} |',
    );
  }

  final incompletas = rows.where((row) => row.n < total).toList();
  if (incompletas.isNotEmpty) {
    stdout.writeln(
      '\n⚠ ${incompletas.length} de ${rows.length} filas están incompletas y '
      '**no son comparables** con las demás:',
    );
    for (final row in incompletas) {
      stdout.writeln(
        '  ${row.serializer}/${row.model}/${row.mode}: ${row.n} de $total casos',
      );
    }
    stdout.writeln(
      '  Volvé a correr con --delay más alto, o con menos ejes por vez.',
    );
  }

  final withFailures = rows.where((row) => row.failures.isNotEmpty);
  if (withFailures.isNotEmpty) {
    stdout.writeln('\nFallos:');
    for (final row in withFailures) {
      stdout.writeln('  ${row.serializer}/${row.model}/${row.mode}:');
      for (final failure in row.failures) {
        stdout.writeln('    $failure');
      }
    }
  }
}

Map<String, String> _parseArgs(List<String> arguments) {
  final options = <String, String>{};
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (!argument.startsWith('--')) continue;
    final name = argument.substring(2);
    final hasValue = i + 1 < arguments.length && !arguments[i + 1].startsWith('--');
    options[name] = hasValue ? arguments[++i] : '';
  }
  return options;
}

List<LayoutSerializer> _pickSerializers(String? csv) {
  if (csv == null || csv.isEmpty) return kLayoutSerializers;
  final wanted = csv.split(',').map((s) => s.trim()).toSet();
  return kLayoutSerializers.where((s) => wanted.contains(s.id)).toList();
}

List<ModelOption> _pickModels(String? csv) {
  if (csv == null || csv.isEmpty) return [kDefaultModel];
  final wanted = csv.split(',').map((s) => s.trim()).toSet();
  return kModelOptions.where((m) => wanted.contains(m.id)).toList();
}

List<OutputMode> _pickModes(String? csv) {
  if (csv == null || csv.isEmpty) return [OutputMode.schema];
  final wanted = csv.split(',').map((s) => s.trim()).toSet();
  return OutputMode.values.where((m) => wanted.contains(m.name)).toList();
}
