import 'model_option.dart';
import 'structured_note.dart';

/// La llamada al modelo, detrás de una interfaz.
///
/// Hay dos implementaciones: [GeminiClient], que sale a la red, y
/// [FakeLlmClient], que devuelve una respuesta fija. La segunda no es decoración
/// para los tests: permite recorrer la app entera sin key y sin gastar tokens, y
/// hace que el parseo del markdown se pueda testear sin red.
abstract class LlmClient {
  /// Paso 4 de la especificación: markdown libre, **sin schema**. La idea es ver
  /// qué devuelve el modelo antes de restringirlo; el paso 5 agrega la variante
  /// con structured output y su propio método.
  Future<ModelReply> writeMarkdown({
    required String serializedOcr,
    required ModelOption model,
  });

  /// Paso 5: el modelo devuelve datos contra un schema, y de ahí sale el markdown.
  ///
  /// Sigue existiendo [writeMarkdown] al lado y no se borró: pedir markdown libre
  /// contra pedir un schema es el tercer eje que el paso 7 va a medir, junto con
  /// el formato de serialización y el modelo.
  Future<ModelReply> structureNote({
    required String serializedOcr,
    required ModelOption model,
  });
}

/// Cómo se le pide la nota al modelo.
///
/// Los dos caminos conviven porque la comparación entre ellos es el tercer eje de
/// las evals, junto con el formato de serialización y el modelo. Borrar el de
/// markdown libre al llegar al schema habría dejado sin línea de base la pregunta
/// "¿cuánto aporta imponer la estructura?".
enum OutputMode {
  schema(
    'Con schema',
    'El modelo devuelve datos contra un responseSchema y el markdown lo arma la '
        'app. El formato deja de depender de que el modelo obedezca.',
  ),
  freeMarkdown(
    'Markdown libre',
    'El modelo escribe el markdown directo. Es la línea de base: mide cuánto '
        'aporta imponer la estructura.',
  );

  const OutputMode(this.label, this.note);

  final String label;
  final String note;
}

/// Lo que devolvió el modelo, con lo que costó.
///
/// Los contadores de tokens vienen del `usageMetadata` de la respuesta: son el
/// costo real, no una estimación por caracteres. Es el número que va a la tabla
/// de costo por foto del README.
class ModelReply {
  const ModelReply({
    required this.markdown,
    required this.elapsed,
    this.promptTokens,
    this.outputTokens,
    this.finishReason,
    this.modelVersion,
    this.note,
    this.rawJson,
    this.warnings = const [],
  });

  /// El markdown listo para copiar. En el camino con schema no lo escribe el
  /// modelo: sale de `renderNoteMarkdown` sobre [note], así que es determinista y
  /// es lo que el runner del paso 7 puede diferenciar contra el golden set.
  final String markdown;

  final Duration elapsed;

  final int? promptTokens;
  final int? outputTokens;

  /// `STOP` es lo normal. Cualquier otra cosa —`MAX_TOKENS`, `SAFETY`— quiere
  /// decir que el markdown está incompleto, y eso hay que mostrarlo: una nota
  /// cortada a la mitad se ve igual de prolija que una completa.
  final String? finishReason;

  /// La versión concreta que atendió el pedido. Un alias como `gemini-2.5-flash`
  /// puede apuntar a distintas versiones con el tiempo, así que sin esto los
  /// resultados de las evals no serían reproducibles.
  final String? modelVersion;

  /// La nota parseada. `null` cuando se pidió markdown libre, sin schema.
  final StructuredNote? note;

  /// El JSON tal como vino, para poder mirarlo cuando el render no cuadra.
  final String? rawJson;

  /// Entradas que el parseo estricto descartó. Vacío es la respuesta buena.
  ///
  /// Se cuentan y se muestran en vez de ignorarse: un modelo que acierta el
  /// contenido pero devuelve tres entradas inválidas por foto no es equivalente a
  /// uno que devuelve cero, y sin esta cuenta las evals no verían la diferencia.
  final List<String> warnings;

  bool get structured => note != null;

  bool get truncated => finishReason != null && finishReason != 'STOP';

  int? get totalTokens => promptTokens == null || outputTokens == null
      ? null
      : promptTokens! + outputTokens!;
}

/// Por qué falló la llamada. Cada caso tiene una acción distinta para el usuario,
/// y por eso son casos distintos y no un solo string de error.
enum LlmFailure {
  /// No hay key configurada todavía.
  missingKey,

  /// La key existe pero el proveedor la rechazó.
  invalidKey,

  /// Se agotó la cuota del tier gratuito. Se reintenta más tarde, no se arregla.
  rateLimited,

  /// No hay red, o no se llegó al servidor.
  network,

  /// Los filtros de contenido del proveedor cortaron la respuesta.
  blocked,

  /// Respondió 5xx: es del lado del proveedor.
  server,

  /// Respondió 200 pero con algo que no se pudo interpretar.
  badResponse,
}

class LlmException implements Exception {
  const LlmException(this.failure, this.message, {this.detail});

  final LlmFailure failure;

  /// Mensaje listo para mostrar, en el idioma de la app.
  final String message;

  /// Lo que dijo el proveedor. No se muestra por defecto, pero sirve cuando el
  /// mensaje amable no alcanza para entender qué pasó.
  final String? detail;

  @override
  String toString() =>
      'LlmException(${failure.name}): $message${detail == null ? '' : ' — $detail'}';
}
