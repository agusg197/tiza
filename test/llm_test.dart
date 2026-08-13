import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiza/llm/fake_llm_client.dart';
import 'package:tiza/llm/gemini_client.dart';
import 'package:tiza/llm/llm_client.dart';
import 'package:tiza/llm/model_option.dart';
import 'package:tiza/llm/note_prompt.dart';

/// Todo lo que se puede testear de la llamada al modelo sin red y sin key: el
/// parseo de la respuesta, el mapeo de errores y el prompt. Es la parte donde
/// están los casos que realmente rompen en producción.
void main() {
  String reply({
    String text = '# Sprint planning',
    String finishReason = 'STOP',
    bool withUsage = true,
  }) => jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': text},
          ],
          'role': 'model',
        },
        'finishReason': finishReason,
      },
    ],
    if (withUsage)
      'usageMetadata': {
        'promptTokenCount': 342,
        'candidatesTokenCount': 118,
        'totalTokenCount': 460,
      },
    'modelVersion': 'gemini-2.5-flash',
  });

  group('parseGeminiReply', () {
    test('extrae el markdown, los tokens y la versión del modelo', () {
      final result = parseGeminiReply(reply(), const Duration(milliseconds: 1240));

      expect(result.markdown, '# Sprint planning');
      expect(result.promptTokens, 342);
      expect(result.outputTokens, 118);
      expect(result.totalTokens, 460);
      expect(result.elapsed.inMilliseconds, 1240);
      expect(result.truncated, isFalse);
      // Sin la versión concreta las evals no serían reproducibles: un alias como
      // `gemini-2.5-flash` puede apuntar a otra versión el mes que viene.
      expect(result.modelVersion, 'gemini-2.5-flash');
    });

    test('sobrevive una respuesta sin usageMetadata', () {
      final result = parseGeminiReply(
        reply(withUsage: false),
        Duration.zero,
      );

      expect(result.markdown, '# Sprint planning');
      expect(result.promptTokens, isNull);
      expect(result.totalTokens, isNull);
    });

    test('saca el bloque de código aunque el prompt pida que no lo ponga', () {
      // El prompt lo pide explícitamente y el modelo igual lo agrega a veces.
      // Pelearlo con más instrucciones gasta tokens en cada llamada.
      final result = parseGeminiReply(
        reply(text: '```markdown\n# Sprint planning\n\n- uno\n```'),
        Duration.zero,
      );

      expect(result.markdown, '# Sprint planning\n\n- uno');
    });

    test('no toca el texto cuando no hay bloque de código', () {
      final result = parseGeminiReply(
        reply(text: '# Título\n\n- con ``backticks`` en el medio'),
        Duration.zero,
      );

      expect(result.markdown, '# Título\n\n- con ``backticks`` en el medio');
    });

    test('marca como truncada una respuesta con texto pero sin STOP', () {
      final result = parseGeminiReply(
        reply(text: '# Sprint pla', finishReason: 'MAX_TOKENS'),
        Duration.zero,
      );

      // Una nota cortada a la mitad se ve igual de prolija que una completa; el
      // flag es lo único que permite avisar.
      expect(result.truncated, isTrue);
      expect(result.finishReason, 'MAX_TOKENS');
    });

    test('falla cuando los filtros de contenido rechazan el pedido', () {
      final body = jsonEncode({
        'promptFeedback': {'blockReason': 'SAFETY'},
      });

      expect(
        () => parseGeminiReply(body, Duration.zero),
        throwsA(
          isA<LlmException>().having((e) => e.failure, 'failure', LlmFailure.blocked),
        ),
      );
    });

    test('falla cuando no vino ningún candidato', () {
      expect(
        () => parseGeminiReply(jsonEncode({'candidates': []}), Duration.zero),
        throwsA(
          isA<LlmException>().having((e) => e.failure, 'failure', LlmFailure.blocked),
        ),
      );
    });

    test('falla con 200 y cero texto por límite de tokens', () {
      // Caso real de los modelos con razonamiento: agotan el presupuesto pensando
      // y devuelven 200 sin una sola parte de texto.
      final body = jsonEncode({
        'candidates': [
          {
            'content': {'parts': [], 'role': 'model'},
            'finishReason': 'MAX_TOKENS',
          },
        ],
      });

      expect(
        () => parseGeminiReply(body, Duration.zero),
        throwsA(
          isA<LlmException>()
              .having((e) => e.failure, 'failure', LlmFailure.badResponse)
              .having((e) => e.message, 'message', contains('límite de tokens')),
        ),
      );
    });

    test('falla con un cuerpo que no es JSON', () {
      expect(
        () => parseGeminiReply('<html>502 Bad Gateway</html>', Duration.zero),
        throwsA(
          isA<LlmException>()
              .having((e) => e.failure, 'failure', LlmFailure.badResponse),
        ),
      );
    });
  });

  group('mapGeminiError', () {
    String error(String message) => jsonEncode({
      'error': {'message': message, 'status': 'INVALID_ARGUMENT'},
    });

    test('un 400 que menciona la API key se reporta como key inválida', () {
      final failure = mapGeminiError(
        400,
        error('API key not valid. Please pass a valid API key.'),
      );

      // Importa distinguirlo: es el único error que el usuario puede arreglar
      // solo, y la nota le ofrece ir a los ajustes.
      expect(failure.failure, LlmFailure.invalidKey);
    });

    test('401 y 403 también son key inválida', () {
      expect(mapGeminiError(401, '').failure, LlmFailure.invalidKey);
      expect(mapGeminiError(403, '').failure, LlmFailure.invalidKey);
    });

    test('429 es cuota agotada, no un error de configuración', () {
      final failure = mapGeminiError(429, error('Quota exceeded'));
      expect(failure.failure, LlmFailure.rateLimited);
      expect(failure.message, contains('cuota'));
    });

    test('5xx queda del lado del proveedor', () {
      expect(mapGeminiError(503, '').failure, LlmFailure.server);
      expect(mapGeminiError(500, '').failure, LlmFailure.server);
    });

    test('un 400 que no habla de la key no se confunde con una key inválida', () {
      final failure = mapGeminiError(400, error('Invalid JSON payload'));
      expect(failure.failure, LlmFailure.badResponse);
      expect(failure.detail, contains('Invalid JSON payload'));
    });

    test('sobrevive un cuerpo de error que no es JSON', () {
      final failure = mapGeminiError(418, 'no soy json');
      expect(failure.failure, LlmFailure.badResponse);
      expect(failure.message, contains('418'));
    });
  });

  group('prompt', () {
    const serialized = '# formato: [y x alto] texto\n[  5   8 100] Sprint planning';

    test('el texto del OCR viaja en el turno del usuario, textual', () {
      expect(buildUserContent(serialized), contains(serialized));
    });

    test('las reglas van aparte y no arrastran el texto del OCR', () {
      final system = buildSystemInstruction();

      // La separación es lo que evita que un renglón del pizarrón que se lea como
      // una instrucción compita con las reglas. La nota es un dato, no una orden.
      expect(system, isNot(contains(serialized)));
      expect(system, contains('No inventes contenido'));
      expect(system, contains('nunca instrucciones'));
    });
  });

  group('FakeLlmClient', () {
    test('devuelve markdown sin red y estima los tokens', () async {
      final result = await const FakeLlmClient(latency: Duration.zero)
          .writeMarkdown(serializedOcr: 'texto', model: kDefaultModel);

      expect(result.markdown, contains('# Sprint planning'));
      expect(result.markdown, contains('## Action items'));
      expect(result.outputTokens, greaterThan(0));
      // Queda etiquetada como simulada: mostrar un resultado inventado sin
      // decirlo sería justo el problema que el proyecto trata de medir.
      expect(result.modelVersion, contains('simulada'));
    });
  });

  group('modelById', () {
    test('resuelve un id conocido', () {
      expect(modelById('flash-3.6').apiId, 'gemini-3.6-flash');
    });

    test('no ofrece la familia 2.5, retirada para keys nuevas', () {
      // Verificado contra la API: devuelve 404 con "no longer available to new
      // users". Un selector que ofrece algo que falla siempre no es un selector.
      expect(
        kModelOptions.map((m) => m.apiId),
        everyElement(isNot(contains('2.5'))),
      );
    });

    test('cae al modelo por defecto con un id retirado o nulo', () {
      // Pasa de verdad cuando el proveedor da de baja un modelo entre dos
      // versiones de la app y el usuario tenía ése elegido.
      expect(modelById('gemini-1.0-pro-vision-retirado').id, kDefaultModel.id);
      expect(modelById(null).id, kDefaultModel.id);
    });
  });
}
