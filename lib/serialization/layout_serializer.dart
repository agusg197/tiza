import '../ocr/models/ocr_result.dart';

/// Convierte un [OcrResult] en el texto que se le manda al LLM.
///
/// Es una interfaz y no una función porque **el formato es la variable que
/// vamos a mover en las evals**: correr el mismo golden set con el mismo modelo
/// y dos serializadores distintos aísla exactamente cuánto aporta el layout.
/// Ese antes/después es el entregable del proyecto, así que la comparación tiene
/// que ser un cambio de valor, no un cambio de código.
abstract class LayoutSerializer {
  const LayoutSerializer();

  /// Identificador estable. Va a la tabla de resultados del README.
  String get id;

  /// Nombre corto para la UI.
  String get label;

  /// Qué hace y por qué existe.
  String get description;

  /// El orden en que este serializador presenta los renglones.
  ///
  /// Está separado de [serialize] porque **el orden se puede medir sin llamar al
  /// modelo**. Es una propiedad determinista de la serialización, y el hallazgo
  /// del paso 3 —que ordenar por `y` intercala las columnas— es exactamente un
  /// problema de orden. Tenerlo como método propio permite iterar sobre esto sin
  /// gastar un token.
  List<OcrLine> order(OcrResult result);

  String serialize(OcrResult result);
}

/// Todos los serializadores disponibles, en orden de menos a más información.
const List<LayoutSerializer> kLayoutSerializers = [
  PlainReadingOrderSerializer(),
  NormalizedLayoutSerializer(),
  ColumnAwareSerializer(),
];

/// Los bloques en el orden que los devuelve MLKit, sin coordenadas.
///
/// Es la línea de base. No está acá para ganar: está para medir cuánto se pierde
/// al tirar el layout. Si el serializador con coordenadas no le gana a esto en
/// las evals, las coordenadas no están aportando y hay que cambiar el formato.
class PlainReadingOrderSerializer extends LayoutSerializer {
  const PlainReadingOrderSerializer();

  @override
  String get id => 'plain';

  @override
  String get label => 'Texto plano';

  @override
  String get description =>
      'Los bloques en el orden de lectura de MLKit, sin posiciones. '
      'Línea de base: mide cuánto se pierde al descartar el layout.';

  @override
  List<OcrLine> order(OcrResult result) => result.lines;

  @override
  String serialize(OcrResult result) => result.rawText;
}

/// Una línea por renglón detectado, precedida por su posición y su tamaño
/// normalizados a 0–100.
///
/// ```
/// [03 12 100] Sprint planning
/// [11 15  58] deploy el viernes
/// ```
///
/// Tres decisiones que se pueden discutir, y por eso están anotadas:
///
/// - **Normalizar a 0–100** para que el mismo pizarrón fotografiado a distinta
///   resolución produzca la misma serialización.
/// - **El alto es relativo al texto más grande de la foto**, no a la altura de la
///   imagen. Normalizado contra la imagen, un título y un bullet caen en 4 y 2:
///   dos valores casi indistinguibles. Relativo al máximo, quedan en 100 y 58, y
///   la jerarquía se lee sola.
/// - **Ordena por `y` y desempata por `x`.** Es lo más simple que funciona, y
///   falla de forma conocida cuando el pizarrón está escrito en columnas: los
///   renglones de ambas columnas se intercalan. [ColumnAwareSerializer] existe
///   justamente para arreglar eso, y este se queda como está para poder medir la
///   diferencia.
class NormalizedLayoutSerializer extends LayoutSerializer {
  const NormalizedLayoutSerializer();

  @override
  String get id => 'coords';

  @override
  String get label => 'Coordenadas';

  @override
  String get description =>
      'Una línea por renglón con [y x alto] normalizados a 0–100, ordenados de '
      'arriba hacia abajo. El alto es relativo al texto más grande de la foto, '
      'como señal de jerarquía.';

  @override
  List<OcrLine> order(OcrResult result) =>
      [...result.lines]..sort(_byReadingOrder);

  @override
  String serialize(OcrResult result) => _emitWithCoords(result, order(result));
}

/// Igual que [NormalizedLayoutSerializer] pero ordenando por bloques de layout en
/// vez de por `y`, con **XY-cut**.
///
/// Existe por un hallazgo del paso 3 y no por una idea previa: en la foto de prueba
/// —dos columnas— el orden de MLKit agrupaba bien las columnas y ordenar por `y`
/// las intercalaba. O sea que la mejora "obvia" empeoraba lo único que la línea de
/// base hacía bien. Esto busca las dos cosas a la vez: agrupamiento correcto y la
/// señal de jerarquía que dan las coordenadas.
///
/// XY-cut es el algoritmo clásico de segmentación de página: se busca el hueco de
/// blanco más ancho, se corta ahí, y se repite en cada mitad. La variante acá es
/// que **el eje del corte no está fijado de antemano** — en cada nivel gana el
/// hueco más grande medido en proporción a la imagen. Fijarlo importa: cortando
/// siempre en horizontal primero, en la foto de prueba una banda partía la columna
/// izquierda al medio y el resultado quedaba peor que la línea de base. Con el eje
/// adaptativo, el hueco entre columnas (15% del ancho) le gana al hueco bajo el
/// título (5,6% del alto) y las columnas salen enteras.
class ColumnAwareSerializer extends LayoutSerializer {
  const ColumnAwareSerializer();

  /// Un hueco tiene que medir al menos esto —en proporción al lado
  /// correspondiente— para valer como corte. Por debajo, el espacio entre
  /// renglones de un mismo párrafo empezaría a contar como separación de bloques.
  static const double _minGap = 0.04;

  /// Además, un corte **vertical** tiene que medir al menos esto en alturas de
  /// texto.
  ///
  /// Es la condición que separa una canaleta entre columnas de una sangría, y hace
  /// falta de verdad: sin ella, un encabezado corto con sus bullets corridos a la
  /// derecha deja un hueco que pasa el 4% del ancho, y el algoritmo lo cortaba como
  /// si fueran dos columnas. Con una sola sección el orden salía bien de casualidad
  /// —el encabezado cae a la izquierda de sus bullets—, pero con dos secciones los
  /// encabezados se iban todos adelante y quedaban sueltos.
  ///
  /// La distancia absoluta no distingue los dos casos; la distancia **medida en
  /// alturas de texto** sí: una sangría son dos o tres, una canaleta son varias más.
  ///
  /// El valor no está afinado, y no se puede afinar con los datos que hay. Medido
  /// sobre los cinco casos de `fixtures/` y los ocho de `test/xy_cut_test.dart`:
  ///
  /// - Con 4 o 3, las secciones indentadas salen bien y el caso de dos columnas
  ///   queda con una inversión (entrega la columna derecha antes del bloque de
  ///   abajo de la izquierda).
  /// - Con 2 se arregla el de dos columnas y se rompe el indentado.
  ///
  /// Los dos conjuntos se contradicen porque el hueco de sangría depende del largo
  /// del encabezado, que es contenido y no layout. Probé también exigir que los dos
  /// lados tengan más de un renglón, y que sus rangos de `y` se solapen: ninguna de
  /// las dos separa los casos. Queda en 4 —el valor que sale del razonamiento, no de
  /// ajustar contra cinco imágenes— y la decisión se toma con fotos reales.
  static const double _gutterInLineHeights = 4;

  @override
  String get id => 'columns';

  @override
  String get label => 'Columnas';

  @override
  String get description =>
      'Como coordenadas, pero ordenando por bloques de layout (XY-cut) en vez de '
      'por y: las columnas salen enteras, una después de la otra.';

  @override
  List<OcrLine> order(OcrResult result) {
    if (result.isEmpty) return const [];

    final frame = _referenceFrame(result);
    final lineHeight = _medianLineHeight(result.lines);

    return _xyCut(
      result.lines,
      minGapX: _max(
        frame.width * _minGap,
        lineHeight * _gutterInLineHeights,
      ),
      minGapY: frame.height * _minGap,
    );
  }

  @override
  String serialize(OcrResult result) => _emitWithCoords(result, order(result));
}

double _max(double a, double b) => a > b ? a : b;

/// Altura mediana de los renglones. Mediana y no promedio: un título grande o un
/// renglón basura del OCR no tienen que mover la referencia.
double _medianLineHeight(List<OcrLine> lines) {
  if (lines.isEmpty) return 0;
  final heights = [for (final line in lines) line.box.height]..sort();
  return heights[heights.length ~/ 2];
}

/// Ordena recursivamente cortando por el hueco de blanco más grande.
List<OcrLine> _xyCut(
  List<OcrLine> lines, {
  required double minGapX,
  required double minGapY,
}) {
  if (lines.length <= 1) return [...lines];

  final vertical = _widestGap(lines, vertical: true);
  final horizontal = _widestGap(lines, vertical: false);

  // Los dos huecos se comparan ya normalizados contra su propio umbral, que es lo
  // que hace justa la comparación entre un hueco horizontal y uno vertical.
  final verticalScore = vertical / minGapX;
  final horizontalScore = horizontal / minGapY;

  if (verticalScore < 1 && horizontalScore < 1) {
    // Sin huecos que valgan: acá adentro no hay estructura que respetar.
    return [...lines]..sort(_byReadingOrder);
  }

  final cutVertically = verticalScore >= horizontalScore;
  final groups = _splitOnAxis(
    lines,
    minGap: cutVertically ? minGapX : minGapY,
    vertical: cutVertically,
  );

  // Si el corte no separó nada, no hay recursión posible y se corta acá para no
  // caer en recursión infinita.
  if (groups.length <= 1) return [...lines]..sort(_byReadingOrder);

  return [
    for (final group in groups)
      ..._xyCut(group, minGapX: minGapX, minGapY: minGapY),
  ];
}

/// El hueco más grande sobre un eje, o 0 si los renglones se solapan de punta a
/// punta.
double _widestGap(List<OcrLine> lines, {required bool vertical}) {
  final intervals = [
    for (final line in lines)
      vertical
          ? (start: line.box.left, end: line.box.right)
          : (start: line.box.top, end: line.box.bottom),
  ]..sort((a, b) => a.start.compareTo(b.start));

  var reach = intervals.first.end;
  var widest = 0.0;
  for (final interval in intervals.skip(1)) {
    final gap = interval.start - reach;
    if (gap > widest) widest = gap;
    if (interval.end > reach) reach = interval.end;
  }
  return widest;
}

/// Agrupa los renglones por los huecos de un eje, en orden de aparición.
List<List<OcrLine>> _splitOnAxis(
  List<OcrLine> lines, {
  required double minGap,
  required bool vertical,
}) {
  double start(OcrLine line) => vertical ? line.box.left : line.box.top;
  double end(OcrLine line) => vertical ? line.box.right : line.box.bottom;

  final sorted = [...lines]..sort((a, b) => start(a).compareTo(start(b)));
  final groups = <List<OcrLine>>[];
  var current = <OcrLine>[sorted.first];
  var reach = end(sorted.first);

  for (final line in sorted.skip(1)) {
    if (start(line) - reach > minGap) {
      groups.add(current);
      current = [line];
      reach = end(line);
    } else {
      current.add(line);
      if (end(line) > reach) reach = end(line);
    }
  }
  groups.add(current);
  return groups;
}

/// El formato `[y x alto] texto`, compartido por los dos serializadores con
/// coordenadas. Lo único que cambia entre ellos es el orden de [ordered], y por eso
/// el emisor está acá afuera: si el formato se duplicara, una comparación entre los
/// dos podría estar midiendo una diferencia de formato en vez de una de orden.
String _emitWithCoords(OcrResult result, List<OcrLine> ordered) {
  if (result.isEmpty) return '';

  final frame = _referenceFrame(result);
  final maxHeight = result.maxLineHeight;

  final buffer = StringBuffer()
    ..writeln('# formato: [y x alto] texto')
    ..writeln('# y, x: esquina superior izquierda del renglón, 0-100 sobre la imagen')
    ..writeln('# alto: 0-100 relativo al texto más grande de la imagen');

  for (final line in ordered) {
    final y = _percent(line.box.top - frame.top0, frame.height);
    final x = _percent(line.box.left - frame.left0, frame.width);
    final h = maxHeight == 0 ? 0 : _percent(line.box.height, maxHeight);
    buffer.writeln('[${_pad(y)} ${_pad(x)} ${_pad(h)}] ${line.text}');
  }

  return buffer.toString().trimRight();
}

/// Marco contra el que se normaliza. Normalmente es la imagen; si no se pudo leer
/// su tamaño, cae al rectángulo que envuelve el texto detectado.
({double width, double height, double left0, double top0}) _referenceFrame(
  OcrResult result,
) {
  if (result.imageWidth > 0 && result.imageHeight > 0) {
    return (
      width: result.imageWidth.toDouble(),
      height: result.imageHeight.toDouble(),
      left0: 0,
      top0: 0,
    );
  }
  final bounds = result.contentBounds!;
  return (
    width: bounds.width == 0 ? 1 : bounds.width,
    height: bounds.height == 0 ? 1 : bounds.height,
    left0: bounds.left,
    top0: bounds.top,
  );
}

int _percent(double value, double total) =>
    total <= 0 ? 0 : (value / total * 100).round().clamp(0, 100);

/// Ancho fijo de 3 para que las columnas se lean alineadas de un vistazo.
String _pad(int value) => value.toString().padLeft(3);

int _byReadingOrder(OcrLine a, OcrLine b) {
  final byTop = a.box.top.compareTo(b.box.top);
  return byTop != 0 ? byTop : a.box.left.compareTo(b.box.left);
}
