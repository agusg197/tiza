/// Los modelos entre los que se puede elegir.
///
/// El tipo es agnóstico del proveedor —separa el `id` estable del `apiId` que
/// espera la API— por la misma razón por la que [LayoutSerializer] es una
/// interfaz: el paso 7 pide correr el golden set cambiando el modelo sin tocar
/// código. Con dos serializadores y estos modelos, la tabla de resultados pasa de
/// ser una columna a ser una matriz.
library;

class ModelOption {
  const ModelOption({
    required this.id,
    required this.apiId,
    required this.label,
    required this.note,
  });

  /// Identificador estable, corto, para la tabla de resultados del README.
  /// No cambia aunque el proveedor renombre el modelo.
  final String id;

  /// El string exacto que va en la URL del proveedor.
  final String apiId;

  /// Nombre para la UI.
  final String label;

  /// Para qué sirve y qué se espera de él. Se muestra en los ajustes.
  final String note;

  @override
  bool operator ==(Object other) => other is ModelOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Sólo modelos Flash y Flash-Lite: son los que están en el tier gratuito de la
/// API de Gemini. Los Pro quedaron en pago, así que no entran acá — un selector
/// que ofrece algo que va a fallar no es un selector.
///
/// Por esa misma razón **no está la familia 2.5**, que era la que sugería la
/// especificación del proyecto. Probada contra la API con una key nueva, devuelve
/// 404 con este mensaje, tanto para `gemini-2.5-flash` como para
/// `gemini-2.5-flash-lite`:
///
/// > This model models/gemini-2.5-flash is no longer available to new users.
///
/// Vale anotar de dónde salió el error: los ids los tomé de un resumen de la
/// documentación, sin probarlos. La lección es que un id de modelo no se verifica
/// leyendo docs, se verifica haciendo la llamada.
const List<ModelOption> kModelOptions = [
  _flashLite35,
  ModelOption(
    id: 'flash-3.5',
    apiId: 'gemini-3.5-flash',
    label: '3.5 Flash',
    note: 'Un escalón más arriba. Sirve para medir cuánto techo queda.',
  ),
  ModelOption(
    id: 'flash-3.6',
    apiId: 'gemini-3.6-flash',
    label: '3.6 Flash',
    note: 'El más capaz de los que entran en el tier gratuito.',
  ),
];

// Con nombre propio y no como `kModelOptions[0]`: indexar una lista no es una
// expresión constante en Dart, y este valor tiene que ser const para poder
// inicializar campos con él.
const ModelOption _flashLite35 = ModelOption(
  id: 'flash-lite-3.5',
  apiId: 'gemini-3.5-flash-lite',
  label: '3.5 Flash-Lite',
  note: 'El más chico y barato. Es el piso: si acá ya sale bien, no hay razón '
      'para pagar más. Verificado contra la API.',
);

/// El piso. La especificación pide empezar por lo barato, y además es el único de
/// la lista con una llamada real verificada de punta a punta.
const ModelOption kDefaultModel = _flashLite35;

ModelOption modelById(String? id) => kModelOptions.firstWhere(
  (option) => option.id == id,
  orElse: () => kDefaultModel,
);
