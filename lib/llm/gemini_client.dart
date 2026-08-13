import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'llm_client.dart';
import 'model_option.dart';
import 'note_prompt.dart';
import 'note_schema.dart';
import 'structured_note.dart';

/// Cliente de la API de Gemini.
///
/// Los dos caminos —markdown libre y schema— comparten el mismo POST y se
/// diferencian sólo en la instrucción de sistema y en si va `responseSchema`. El
/// parseo y el mapeo de errores viven en funciones puras al final del archivo,
/// fuera de la clase: así se testean con un JSON de ejemplo, sin red y sin key,
/// que es donde están los casos que importan.
class GeminiClient implements LlmClient {
  GeminiClient({
    required this.apiKey,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : _http = httpClient ?? http.Client();

  final String apiKey;
  final Duration timeout;
  final http.Client _http;

  static const String _host = 'generativelanguage.googleapis.com';

  @override
  Future<ModelReply> writeMarkdown({
    required String serializedOcr,
    required ModelOption model,
  }) async {
    final raw = await _generate(
      model: model,
      system: buildSystemInstruction(),
      user: buildUserContent(serializedOcr),
    );
    return parseGeminiReply(raw.body, raw.elapsed);
  }

  @override
  Future<ModelReply> structureNote({
    required String serializedOcr,
    required ModelOption model,
  }) async {
    final raw = await _generate(
      model: model,
      system: buildStructuredSystemInstruction(),
      user: buildUserContent(serializedOcr),
      responseSchema: kNoteResponseSchema,
    );
    return buildStructuredReply(raw.body, raw.elapsed);
  }

  Future<({String body, Duration elapsed})> _generate({
    required ModelOption model,
    required String system,
    required String user,
    Map<String, dynamic>? responseSchema,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const LlmException(
        LlmFailure.missingKey,
        'Falta configurar la API key de Gemini.',
      );
    }

    // Uri.parse en vez de Uri.https: el endpoint lleva dos puntos en el último
    // segmento (`:generateContent`) y conviene armarlo tal cual, sin depender de
    // cómo codifique cada versión de Dart ese carácter. El apiId sale de
    // kModelOptions, no de entrada del usuario.
    final uri = Uri.parse(
      'https://$_host/v1beta/models/${model.apiId}:generateContent',
    );

    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': user},
          ],
        },
      ],
      'generationConfig': {
        // Temperatura 0: sin esto, correr el golden set dos veces da resultados
        // distintos y las evals no sirven para comparar nada.
        'temperature': 0,
        'maxOutputTokens': 4096,
        if (responseSchema != null) ...{
          'responseMimeType': 'application/json',
          'responseSchema': responseSchema,
        },
      },
    });

    final stopwatch = Stopwatch()..start();
    final http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: {
              'content-type': 'application/json',
              // Header y no `?key=`: en la URL la key queda en logs de acceso,
              // historiales y cualquier proxy del camino.
              'x-goog-api-key': apiKey,
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw LlmException(
        LlmFailure.network,
        'El modelo no respondió en ${timeout.inSeconds} segundos.',
      );
    } on SocketException catch (error) {
      throw LlmException(
        LlmFailure.network,
        'No hay conexión a internet.',
        detail: error.message,
      );
    } on http.ClientException catch (error) {
      throw LlmException(
        LlmFailure.network,
        'Falló la conexión con el modelo.',
        detail: error.message,
      );
    }
    stopwatch.stop();

    if (response.statusCode != 200) {
      throw mapGeminiError(response.statusCode, response.body);
    }

    // `bodyBytes` decodificado como UTF-8 a mano: `response.body` usa latin-1
    // cuando la respuesta no declara charset, y ahí se rompen los acentos.
    return (body: utf8.decode(response.bodyBytes), elapsed: stopwatch.elapsed);
  }

  void close() => _http.close();
}

/// Convierte el cuerpo de una respuesta 200 en un [ModelReply].
///
/// Lanza [LlmException] si el 200 no trae texto usable, que pasa más seguido de
/// lo que parece: los filtros de contenido pueden devolver 200 con cero
/// candidatos, y un modelo con presupuesto de razonamiento agotado devuelve 200
/// con `MAX_TOKENS` y ninguna parte de texto.
ModelReply parseGeminiReply(String responseBody, Duration elapsed) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(responseBody) as Map<String, dynamic>;
  } catch (_) {
    throw const LlmException(
      LlmFailure.badResponse,
      'La respuesta del modelo no era JSON válido.',
    );
  }

  final blockReason =
      (json['promptFeedback'] as Map<String, dynamic>?)?['blockReason'];
  if (blockReason != null) {
    throw LlmException(
      LlmFailure.blocked,
      'Los filtros de contenido de Google rechazaron el pedido.',
      detail: 'blockReason: $blockReason',
    );
  }

  final candidates = json['candidates'] as List?;
  if (candidates == null || candidates.isEmpty) {
    throw const LlmException(
      LlmFailure.blocked,
      'El modelo no devolvió ningún candidato.',
    );
  }

  final candidate = candidates.first as Map<String, dynamic>;
  final finishReason = candidate['finishReason'] as String?;
  final parts =
      (candidate['content'] as Map<String, dynamic>?)?['parts'] as List?;

  final text = (parts ?? [])
      .map((part) => (part as Map<String, dynamic>)['text'])
      .whereType<String>()
      .join();

  final usage = json['usageMetadata'] as Map<String, dynamic>?;
  final promptTokens = usage?['promptTokenCount'] as int?;
  final outputTokens = usage?['candidatesTokenCount'] as int?;

  if (text.trim().isEmpty) {
    throw LlmException(
      LlmFailure.badResponse,
      finishReason == 'MAX_TOKENS'
          ? 'El modelo agotó el límite de tokens antes de escribir nada.'
          : 'El modelo respondió sin texto.',
      detail: 'finishReason: $finishReason',
    );
  }

  return ModelReply(
    markdown: _stripCodeFence(text.trim()),
    elapsed: elapsed,
    promptTokens: promptTokens,
    outputTokens: outputTokens,
    finishReason: finishReason,
    modelVersion: json['modelVersion'] as String?,
  );
}

/// Igual que [parseGeminiReply], pero el texto del candidato es el JSON del
/// schema: se parsea, se valida y de ahí se arma el markdown.
///
/// El markdown no lo escribe el modelo, lo escribe `renderNoteMarkdown`. Es la
/// diferencia central del paso 5: el formato deja de depender de que el modelo
/// obedezca y pasa a ser una función determinista sobre datos validados.
ModelReply buildStructuredReply(String responseBody, Duration elapsed) {
  // La primera pasada extrae el texto y el uso de tokens. Acá `markdown` todavía
  // no es markdown: es el JSON que devolvió el modelo.
  final base = parseGeminiReply(responseBody, elapsed);
  final parsed = parseStructuredNote(base.markdown);

  return ModelReply(
    markdown: renderNoteMarkdown(parsed.note),
    elapsed: base.elapsed,
    promptTokens: base.promptTokens,
    outputTokens: base.outputTokens,
    finishReason: base.finishReason,
    modelVersion: base.modelVersion,
    note: parsed.note,
    rawJson: base.markdown,
    warnings: parsed.warnings,
  );
}

/// El prompt de markdown libre pide que no envuelva la respuesta en un bloque de
/// código, y aun así a veces lo hace. Se saca acá y no en el prompt porque
/// pelearlo con más instrucciones gasta tokens en cada llamada; esto son diez
/// líneas una vez. Con schema el problema no existe.
String _stripCodeFence(String text) {
  if (!text.startsWith('```')) return text;

  final lines = text.split('\n');
  if (lines.length < 2) return text;

  // Primera línea: ``` o ```markdown. Última: ``` si cerró bien.
  final closing = lines.last.trim() == '```' ? lines.length - 1 : lines.length;
  return lines.sublist(1, closing).join('\n').trim();
}

/// Traduce un error HTTP del proveedor a algo que el usuario pueda accionar.
LlmException mapGeminiError(int statusCode, String responseBody) {
  String? providerMessage;
  try {
    final json = jsonDecode(responseBody) as Map<String, dynamic>;
    providerMessage = (json['error'] as Map<String, dynamic>?)?['message'] as String?;
  } catch (_) {
    // Cuerpo no-JSON: nos quedamos con el código de estado.
  }

  final mentionsKey =
      providerMessage != null && providerMessage.toLowerCase().contains('api key');

  if (statusCode == 401 || statusCode == 403 || (statusCode == 400 && mentionsKey)) {
    return LlmException(
      LlmFailure.invalidKey,
      'Google rechazó la API key. Revisala en los ajustes.',
      detail: providerMessage,
    );
  }

  if (statusCode == 429) {
    return LlmException(
      LlmFailure.rateLimited,
      'Se agotó la cuota gratuita por ahora. Probá de nuevo en un rato o elegí '
      'un modelo más chico.',
      detail: providerMessage,
    );
  }

  if (statusCode >= 500) {
    return LlmException(
      LlmFailure.server,
      'El modelo está caído o sobrecargado ($statusCode).',
      detail: providerMessage,
    );
  }

  return LlmException(
    LlmFailure.badResponse,
    'La API devolvió $statusCode.',
    detail: providerMessage,
  );
}
