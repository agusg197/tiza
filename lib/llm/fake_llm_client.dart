import 'llm_client.dart';
import 'model_option.dart';
import 'structured_note.dart';

/// Devuelve una respuesta fija, sin red y sin key.
///
/// Sirve para dos cosas concretas: recorrer la app completa antes de tener una
/// key, y testear todo lo que pasa **después** de la llamada —el visor, el
/// markdown, los estados— sin gastar un token ni depender de internet.
///
/// El markdown que devuelve corresponde a la imagen de prueba del paso 3, así que
/// el resultado se puede comparar contra lo que produce el modelo real.
class FakeLlmClient implements LlmClient {
  const FakeLlmClient({this.latency = const Duration(milliseconds: 600)});

  final Duration latency;

  @override
  Future<ModelReply> writeMarkdown({
    required String serializedOcr,
    required ModelOption model,
  }) async {
    // La demora está a propósito: sin ella no se ve el estado de carga y es
    // justo el estado que más fácil se rompe.
    await Future<void>.delayed(latency);

    return ModelReply(
      markdown: _respuesta,
      elapsed: latency,
      // Aproximación por caracteres, sólo para que el panel tenga algo que
      // mostrar. Los tokens de verdad los reporta el proveedor.
      promptTokens: (serializedOcr.length / 4).round(),
      outputTokens: (_respuesta.length / 4).round(),
      finishReason: 'STOP',
      modelVersion: '${model.apiId} (respuesta simulada)',
    );
  }

  @override
  Future<ModelReply> structureNote({
    required String serializedOcr,
    required ModelOption model,
  }) async {
    await Future<void>.delayed(latency);

    // Incluye a propósito dos entradas inválidas —un bullet vacío y un action
    // item sin texto— para que el camino de validación estricta se pueda ver en
    // pantalla sin tener que provocar un error del modelo real.
    final parsed = parseStructuredNote(_respuestaJson);

    return ModelReply(
      markdown: renderNoteMarkdown(parsed.note),
      elapsed: latency,
      promptTokens: (serializedOcr.length / 4).round(),
      outputTokens: (_respuestaJson.length / 4).round(),
      finishReason: 'STOP',
      modelVersion: '${model.apiId} (respuesta simulada)',
      note: parsed.note,
      rawJson: _respuestaJson,
      warnings: parsed.warnings,
    );
  }
}

const String _respuestaJson = '''
{
  "title": "Sprint planning",
  "sections": [
    {
      "heading": "Objetivos",
      "depth": 0,
      "bullets": ["cerrar el checkout", "migrar la base", "medir latencia", ""]
    },
    {
      "heading": "Riesgos",
      "depth": 0,
      "bullets": ["el proveedor no responde"]
    }
  ],
  "actionItems": [
    { "text": "revisar metricas", "owner": "Ana" },
    { "text": "deploy el viernes", "owner": "Beto" },
    { "text": "hablar con legales", "owner": "Cami" },
    { "text": "", "owner": null }
  ]
}''';

const String _respuesta = '''
# Sprint planning

## Objetivos

- cerrar el checkout
- migrar la base
- medir latencia

## Riesgos

- el proveedor no responde

## Action items

- Ana: revisar metricas
- Beto: deploy el viernes
- Cami: hablar con legales''';
