import 'package:flutter_test/flutter_test.dart';
import 'package:tiza/ocr/models/ocr_result.dart';
import 'package:tiza/serialization/layout_serializer.dart';

/// Estos tests corren en la máquina, sin emulador ni MLKit. Es la razón por la
/// que [OcrResult] no arrastra tipos nativos: la parte del pipeline donde se
/// toman las decisiones difíciles es la que se puede testear gratis.
void main() {
  // Un pizarrón de 1000x2000 con un título grande y dos bullets más chicos.
  // Los bloques vienen desordenados a propósito: MLKit devuelve su propio orden
  // de lectura y en un pizarrón se equivoca seguido.
  OcrResult board({int imageWidth = 1000, int imageHeight = 2000}) => OcrResult(
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    blocks: [
      OcrBlock(
        text: 'Sprint planning',
        box: const OcrRect(left: 100, top: 100, width: 600, height: 80),
        lines: const [
          OcrLine(
            text: 'Sprint planning',
            box: OcrRect(left: 100, top: 100, width: 600, height: 80),
            confidence: 0.9,
          ),
        ],
      ),
      OcrBlock(
        text: 'deploy el viernes\nrevisar métricas',
        box: const OcrRect(left: 150, top: 300, width: 500, height: 140),
        lines: const [
          OcrLine(
            text: 'deploy el viernes',
            box: OcrRect(left: 150, top: 400, width: 500, height: 40),
            confidence: 0.7,
          ),
          OcrLine(
            text: 'revisar métricas',
            box: OcrRect(left: 150, top: 300, width: 500, height: 40),
            confidence: 0.8,
          ),
        ],
      ),
    ],
  );

  group('PlainReadingOrderSerializer', () {
    const serializer = PlainReadingOrderSerializer();

    test('respeta el orden de MLKit y no agrega posiciones', () {
      expect(
        serializer.serialize(board()),
        'Sprint planning\ndeploy el viernes\nrevisar métricas',
      );
    });

    test('sobre un resultado vacío devuelve vacío', () {
      expect(serializer.serialize(OcrResult.empty), isEmpty);
    });
  });

  group('NormalizedLayoutSerializer', () {
    const serializer = NormalizedLayoutSerializer();

    List<String> body(String serialized) => serialized
        .split('\n')
        .where((line) => !line.startsWith('#'))
        .toList();

    test('ordena por y, normaliza a 0-100 y expresa el alto relativo al máximo', () {
      expect(body(serializer.serialize(board())), [
        '[  5  10 100] Sprint planning',
        '[ 15  15  50] revisar métricas',
        '[ 20  15  50] deploy el viernes',
      ]);
    });

    test('incluye una leyenda del formato para que se pueda leer sin contexto', () {
      final serialized = serializer.serialize(board());
      expect(serialized, startsWith('# formato: [y x alto] texto'));
    });

    test('la serialización no depende de la resolución de la foto', () {
      // El mismo pizarrón fotografiado al doble de resolución tiene que producir
      // exactamente el mismo texto. Es el punto de normalizar.
      final small = serializer.serialize(board());
      final large = serializer.serialize(
        OcrResult(
          imageWidth: 2000,
          imageHeight: 4000,
          blocks: [
            for (final block in board().blocks)
              OcrBlock(
                text: block.text,
                box: _scale(block.box, 2),
                lines: [
                  for (final line in block.lines)
                    OcrLine(
                      text: line.text,
                      box: _scale(line.box, 2),
                      confidence: line.confidence,
                    ),
                ],
              ),
          ],
        ),
      );
      expect(large, small);
    });

    test('sin tamaño de imagen normaliza contra el rectángulo del contenido', () {
      // Caso real: no se pudo leer el header del archivo. En vez de dividir por
      // cero, el marco de referencia pasa a ser el texto detectado.
      expect(body(serializer.serialize(board(imageWidth: 0, imageHeight: 0))), [
        '[  0   0 100] Sprint planning',
        '[ 59   8  50] revisar métricas',
        '[ 88   8  50] deploy el viernes',
      ]);
    });

    test('sobre un resultado vacío devuelve vacío, sin leyenda', () {
      expect(serializer.serialize(OcrResult.empty), isEmpty);
    });
  });

  group('OcrResult', () {
    test('aplana las líneas de todos los bloques', () {
      expect(board().lines.map((line) => line.text), [
        'Sprint planning',
        'deploy el viernes',
        'revisar métricas',
      ]);
    });

    test('maxLineHeight toma la línea más alta, no el bloque más alto', () {
      expect(board().maxLineHeight, 80);
    });

    test('promedia la confianza sólo de las líneas que la reportan', () {
      expect(board().averageConfidence, closeTo(0.8, 1e-9));
      expect(OcrResult.empty.averageConfidence, isNull);
    });

    test('sobrevive un round-trip por JSON', () {
      // Este round-trip es lo que hace posible el runner de evals del paso 7:
      // congelar el OCR de cada foto del golden set como fixture y correr las
      // evals sin dispositivo.
      final original = board();
      final restored = OcrResult.fromJson(original.toJson());

      expect(
        const NormalizedLayoutSerializer().serialize(restored),
        const NormalizedLayoutSerializer().serialize(original),
      );
      expect(restored.averageConfidence, original.averageConfidence);
      expect(restored.imageWidth, 1000);
    });
  });

  _columnTests();
}

/// Un pizarrón con título ancho arriba y dos columnas debajo, que es el caso donde
/// el serializador de coordenadas falla y el de columnas existe para arreglar.
OcrResult _twoColumns() {
  OcrLine line(String text, double x, double y, double w, double h) => OcrLine(
    text: text,
    box: OcrRect(left: x, top: y, width: w, height: h),
  );

  final lines = [
    line('Sprint planning', 80, 60, 380, 70),
    line('Objetivos', 100, 220, 250, 45),
    line('cerrar el checkout', 140, 300, 240, 30),
    line('migrar la base', 140, 350, 200, 30),
    line('Action items', 640, 220, 230, 45),
    line('Ana: revisar metricas', 680, 300, 260, 30),
    line('Beto: deploy el viernes', 680, 350, 250, 30),
  ];

  return OcrResult(
    imageWidth: 1200,
    imageHeight: 1600,
    blocks: [
      for (final single in lines)
        OcrBlock(text: single.text, box: single.box, lines: [single]),
    ],
  );
}

void _columnTests() {
  group('ColumnAwareSerializer', () {
    const columns = ColumnAwareSerializer();
    const coords = NormalizedLayoutSerializer();

    List<String> texts(LayoutSerializer serializer, OcrResult result) =>
        [for (final line in serializer.order(result)) line.text];

    test('saca cada columna entera, una después de la otra', () {
      expect(texts(columns, _twoColumns()), [
        'Sprint planning',
        'Objetivos',
        'cerrar el checkout',
        'migrar la base',
        'Action items',
        'Ana: revisar metricas',
        'Beto: deploy el viernes',
      ]);
    });

    test('el serializador por y sí intercala: es el fallo documentado', () {
      // Este test no describe un bug a arreglar, describe la línea de base contra
      // la que se mide. Si algún día deja de intercalar, la comparación entre los
      // dos serializadores pierde sentido y hay que revisarla.
      final order = texts(coords, _twoColumns());
      expect(order.indexOf('Action items'), lessThan(order.indexOf('migrar la base')));
    });

    test('sobre una sola columna coincide con el orden por y', () {
      final single = OcrResult(
        imageWidth: 800,
        imageHeight: 1200,
        blocks: [
          for (final entry in [('Uno', 100.0), ('Dos', 200.0), ('Tres', 300.0)])
            OcrBlock(
              text: entry.$1,
              box: OcrRect(left: 60, top: entry.$2, width: 300, height: 40),
              lines: [
                OcrLine(
                  text: entry.$1,
                  box: OcrRect(left: 60, top: entry.$2, width: 300, height: 40),
                ),
              ],
            ),
        ],
      );

      expect(texts(columns, single), texts(coords, single));
    });

    test('emite el mismo formato que el serializador de coordenadas', () {
      // Si el formato difiriera, comparar los dos en las evals estaría midiendo una
      // diferencia de formato en vez de una de orden.
      final serialized = columns.serialize(_twoColumns());
      expect(serialized, startsWith('# formato: [y x alto] texto'));
      expect(serialized, contains('[  4   7 100] Sprint planning'));
    });

    test('sobre un resultado vacío no explota', () {
      expect(columns.order(OcrResult.empty), isEmpty);
      expect(columns.serialize(OcrResult.empty), isEmpty);
    });
  });

  test('el registro tiene los tres serializadores', () {
    expect(kLayoutSerializers.map((s) => s.id), ['plain', 'coords', 'columns']);
  });
}

OcrRect _scale(OcrRect rect, double factor) => OcrRect(
  left: rect.left * factor,
  top: rect.top * factor,
  width: rect.width * factor,
  height: rect.height * factor,
);
