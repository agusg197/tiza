import 'package:flutter_test/flutter_test.dart';
import 'package:tiza/ocr/models/ocr_result.dart';
import 'package:tiza/serialization/layout_serializer.dart';

/// Casos de layout hostiles para el XY-cut.
///
/// Son tests del algoritmo, con geometría escrita a mano, y no fixtures del golden
/// set: no hay imagen ni MLKit de por medio. La distinción importa. El eje del
/// serializador es sobre **layout**, y el layout se puede hacer difícil sin letra
/// manuscrita; lo que sí necesita fotos reales es la calidad del OCR y la
/// comparación entre modelos.
///
/// El objetivo no es que todo pase: es encontrar dónde se rompe **antes** de que lo
/// encuentre una foto real. Los casos que no pasan quedan documentados como límites
/// conocidos, no borrados.
void main() {
  /// Arma un OcrResult a partir de renglones `(texto, x, y, ancho, alto)`.
  OcrResult board(
    List<(String, double, double, double, double)> lines, {
    int width = 1200,
    int height = 1600,
  }) {
    final built = [
      for (final (text, x, y, w, h) in lines)
        OcrLine(text: text, box: OcrRect(left: x, top: y, width: w, height: h)),
    ];
    return OcrResult(
      imageWidth: width,
      imageHeight: height,
      blocks: [
        for (final line in built)
          OcrBlock(text: line.text, box: line.box, lines: [line]),
      ],
    );
  }

  const columns = ColumnAwareSerializer();

  List<String> order(OcrResult result) =>
      [for (final line in columns.order(result)) line.text];

  test('tres columnas salen enteras y en orden', () {
    final result = board([
      ('Titulo', 80, 60, 400, 70),
      ('A1', 80, 250, 200, 40),
      ('A2', 80, 320, 200, 40),
      ('B1', 500, 250, 200, 40),
      ('B2', 500, 320, 200, 40),
      ('C1', 900, 250, 200, 40),
      ('C2', 900, 320, 200, 40),
    ]);

    expect(order(result), ['Titulo', 'A1', 'A2', 'B1', 'B2', 'C1', 'C2']);
  });

  test('columnas desparejas: una más larga que la otra no descoloca a la corta', () {
    // Ordenar por `y` acá intercala fuerte, porque las filas no se corresponden.
    final result = board([
      ('Izq 1', 80, 200, 250, 40),
      ('Izq 2', 80, 270, 250, 40),
      ('Izq 3', 80, 340, 250, 40),
      ('Izq 4', 80, 410, 250, 40),
      ('Der 1', 700, 230, 250, 40),
      ('Der 2', 700, 300, 250, 40),
    ]);

    expect(order(result), ['Izq 1', 'Izq 2', 'Izq 3', 'Izq 4', 'Der 1', 'Der 2']);
  });

  test('columnas arrancadas a distinta altura siguen saliendo enteras', () {
    final result = board([
      ('Izq 1', 80, 200, 250, 40),
      ('Izq 2', 80, 270, 250, 40),
      ('Der 1', 700, 500, 250, 40),
      ('Der 2', 700, 570, 250, 40),
    ]);

    expect(order(result), ['Izq 1', 'Izq 2', 'Der 1', 'Der 2']);
  });

  test('bullets indentados no se confunden con una columna nueva', () {
    // El riesgo concreto: un encabezado corto y sus bullets corridos a la derecha
    // dejan un hueco vertical entre los dos rangos de x. Si el XY-cut lo tomara
    // como separación de columnas, partiría la sección en dos y el encabezado
    // quedaría suelto.
    final result = board([
      ('Objetivos', 80, 200, 220, 45),
      ('primero', 420, 270, 300, 35),
      ('segundo', 420, 330, 300, 35),
      ('tercero', 420, 390, 300, 35),
    ]);

    expect(order(result), ['Objetivos', 'primero', 'segundo', 'tercero']);
  });

  test('dos secciones indentadas no se parten en encabezados y cuerpo', () {
    // Este es el caso que desenmascara al anterior. Con una sola sección, tratar la
    // indentación como columna daba el orden correcto de casualidad, porque el
    // encabezado cae a la izquierda de sus bullets. Con dos secciones, partir por el
    // hueco de indentación manda los dos encabezados adelante y los deja sueltos:
    //
    //   Objetivos, Riesgos, primero, segundo, tercero   ← lo que salía
    //   Objetivos, primero, segundo, Riesgos, tercero   ← lo correcto
    final result = board([
      ('Objetivos', 80, 200, 220, 45),
      ('primero', 420, 270, 300, 35),
      ('segundo', 420, 330, 300, 35),
      ('Riesgos', 80, 420, 200, 45),
      ('tercero', 420, 490, 300, 35),
    ]);

    expect(order(result), [
      'Objetivos',
      'primero',
      'segundo',
      'Riesgos',
      'tercero',
    ]);
  });

  test('sin hueco entre columnas cae al orden de lectura, sin inventar bloques', () {
    // Dos columnas cuyos rangos de x se solapan: no hay canaleta, así que no hay
    // nada que cortar. Lo correcto es degradar al orden por `y`, no partir por un
    // lugar arbitrario.
    final result = board([
      ('Izq', 80, 200, 600, 40),
      ('Der', 500, 200, 600, 40),
      ('Izq2', 80, 270, 600, 40),
      ('Der2', 500, 270, 600, 40),
    ]);

    expect(order(result), ['Izq', 'Der', 'Izq2', 'Der2']);
  });

  test('un solo renglón no rompe nada', () {
    final result = board([('Solo', 100, 100, 300, 40)]);
    expect(order(result), ['Solo']);
  });

  test('canaleta angosta: límite conocido del umbral del 4%', () {
    // La canaleta mide 36 px sobre 1200 = 3%, por debajo del umbral. El algoritmo
    // no corta y las columnas se intercalan.
    //
    // Queda como test para que el límite esté escrito y medido, no escondido. Bajar
    // el umbral arreglaría este caso y rompería el de los bullets indentados, así
    // que la salida no es tocar el número: es una señal de layout distinta de la
    // distancia. Si aparece en fotos reales, ahí se decide.
    final result = board([
      ('Izq 1', 80, 200, 400, 40),
      ('Der 1', 516, 200, 400, 40),
      ('Izq 2', 80, 270, 400, 40),
      ('Der 2', 516, 270, 400, 40),
    ]);

    expect(order(result), ['Izq 1', 'Der 1', 'Izq 2', 'Der 2']);
  });
}
