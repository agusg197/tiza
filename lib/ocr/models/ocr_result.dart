/// Modelo de dominio del resultado del OCR, en Dart puro.
///
/// A propósito no importa `google_mlkit_*` ni `dart:ui`. Dos razones:
///
/// 1. Todo lo que viene después (serialización del layout, prompt, parseo de la
///    respuesta) se testea con `flutter test` en la máquina, sin emulador.
/// 2. `toJson`/`fromJson` permiten congelar el OCR de una foto como fixture. El
///    runner de evals del paso 7 va a leer esos fixtures en vez de re-correr
///    MLKit: las evals quedan rápidas, deterministas y sin dispositivo.
library;

import 'dart:math' as math;

/// Rectángulo en píxeles de la imagen original, con el origen arriba-izquierda.
class OcrRect {
  const OcrRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  Map<String, dynamic> toJson() => {'l': left, 't': top, 'w': width, 'h': height};

  factory OcrRect.fromJson(Map<String, dynamic> json) => OcrRect(
    left: (json['l'] as num).toDouble(),
    top: (json['t'] as num).toDouble(),
    width: (json['w'] as num).toDouble(),
    height: (json['h'] as num).toDouble(),
  );

  @override
  String toString() => 'OcrRect(l:$left, t:$top, w:$width, h:$height)';
}

/// Una línea de texto reconocida.
///
/// Es la granularidad con la que serializamos. Un [OcrBlock] agrupa líneas
/// cercanas, pero en un pizarrón ese agrupamiento se equivoca seguido: junta un
/// título con el primer bullet, o parte una columna al medio. Serializar por
/// línea y dejar que el modelo agrupe usando las coordenadas evita heredar ese
/// error. Bajar a `TextElement` (palabra) no aporta señal de estructura y
/// multiplica los tokens.
class OcrLine {
  const OcrLine({required this.text, required this.box, this.confidence});

  final String text;
  final OcrRect box;

  /// Confianza que reporta MLKit, 0..1. Es `null` en las plataformas que no la
  /// exponen. Sirve como termómetro de qué tan legible es la letra.
  final double? confidence;

  Map<String, dynamic> toJson() => {
    'text': text,
    'box': box.toJson(),
    if (confidence != null) 'confidence': confidence,
  };

  factory OcrLine.fromJson(Map<String, dynamic> json) => OcrLine(
    text: json['text'] as String,
    box: OcrRect.fromJson(json['box'] as Map<String, dynamic>),
    confidence: (json['confidence'] as num?)?.toDouble(),
  );
}

/// Un bloque de texto: el agrupamiento que propone MLKit.
class OcrBlock {
  const OcrBlock({required this.text, required this.box, required this.lines});

  final String text;
  final OcrRect box;
  final List<OcrLine> lines;

  Map<String, dynamic> toJson() => {
    'text': text,
    'box': box.toJson(),
    'lines': [for (final line in lines) line.toJson()],
  };

  factory OcrBlock.fromJson(Map<String, dynamic> json) => OcrBlock(
    text: json['text'] as String,
    box: OcrRect.fromJson(json['box'] as Map<String, dynamic>),
    lines: [
      for (final line in json['lines'] as List)
        OcrLine.fromJson(line as Map<String, dynamic>),
    ],
  );
}

/// Resultado completo del OCR sobre una imagen.
class OcrResult {
  const OcrResult({
    required this.blocks,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<OcrBlock> blocks;

  /// Dimensiones de la imagen original en píxeles. Pueden ser `0` si no se pudo
  /// leer el header; en ese caso los serializadores normalizan contra
  /// [contentBounds] en lugar de contra la imagen.
  final int imageWidth;
  final int imageHeight;

  static const empty = OcrResult(blocks: [], imageWidth: 0, imageHeight: 0);

  /// Todas las líneas, aplanadas. Sin ordenar: el orden lo decide cada
  /// serializador.
  List<OcrLine> get lines => [for (final block in blocks) ...block.lines];

  bool get isEmpty => lines.isEmpty;

  /// El texto tal cual sale de MLKit, en su orden de lectura. Es la línea de
  /// base contra la que se compara cualquier serialización con layout.
  String get rawText => blocks.map((block) => block.text).join('\n');

  /// Alto de la línea de texto más grande. Es la referencia para expresar
  /// tamaños de forma relativa: "este texto mide el 100% del más grande de la
  /// foto" es una señal de jerarquía mucho más útil que "mide 32 píxeles".
  double get maxLineHeight =>
      lines.fold<double>(0, (acc, line) => math.max(acc, line.box.height));

  /// Confianza promedio de las líneas que la reportan, o `null` si ninguna.
  double? get averageConfidence {
    final values = [
      for (final line in lines)
        if (line.confidence != null) line.confidence!,
    ];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Rectángulo que envuelve todo el texto detectado.
  OcrRect? get contentBounds {
    if (isEmpty) return null;
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    for (final line in lines) {
      left = math.min(left, line.box.left);
      top = math.min(top, line.box.top);
      right = math.max(right, line.box.right);
      bottom = math.max(bottom, line.box.bottom);
    }
    return OcrRect(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
  }

  Map<String, dynamic> toJson() => {
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'blocks': [for (final block in blocks) block.toJson()],
  };

  factory OcrResult.fromJson(Map<String, dynamic> json) => OcrResult(
    imageWidth: json['imageWidth'] as int,
    imageHeight: json['imageHeight'] as int,
    blocks: [
      for (final block in json['blocks'] as List)
        OcrBlock.fromJson(block as Map<String, dynamic>),
    ],
  );
}
