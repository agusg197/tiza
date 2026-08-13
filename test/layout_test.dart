import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiza/ocr/models/ocr_result.dart';
import 'package:tiza/serialization/layout_serializer.dart';
import 'package:tiza/theme/tiza_theme.dart';
import 'package:tiza/ui/widgets/measure_panel.dart';
import 'package:tiza/ui/widgets/serializer_toggle.dart';

/// Regresión de un bug real: los dos paneles usan `Row` con
/// `CrossAxisAlignment.stretch` para que los separadores verticales lleguen de
/// arriba abajo, y viven como hijos **no flexibles** de una `Column`, que les
/// pasa altura sin límite. Estirar contra infinito hace fallar el layout, y el
/// síntoma es que la pantalla entera del resultado se dibuja en blanco, sin
/// romperse de forma visible.
///
/// Montar cada panel como hijo directo de una `Column` reproduce exactamente esa
/// condición de borde, así que estos dos tests fallan si vuelve a aparecer.
void main() {
  final result = OcrResult(
    imageWidth: 1200,
    imageHeight: 1600,
    blocks: [
      OcrBlock(
        text: 'Sprint planning',
        box: const OcrRect(left: 80, top: 60, width: 600, height: 70),
        lines: const [
          OcrLine(
            text: 'Sprint planning',
            box: OcrRect(left: 80, top: 60, width: 600, height: 70),
            confidence: 0.88,
          ),
        ],
      ),
    ],
  );

  Widget mount(Widget panel) => MaterialApp(
    theme: tizaTheme(Brightness.light),
    // Column sin Expanded: es el escenario que le da altura infinita al hijo.
    home: Scaffold(body: Column(children: [panel])),
  );

  testWidgets('MeasurePanel se puede montar con altura sin límite', (tester) async {
    await tester.pumpWidget(
      mount(MeasurePanel(result: result, elapsed: const Duration(milliseconds: 340))),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('340'), findsOneWidget);
    expect(find.text('88'), findsOneWidget);
  });

  testWidgets('SerializerToggle se puede montar con altura sin límite', (tester) async {
    await tester.pumpWidget(
      mount(
        SerializerToggle(
          serializers: kLayoutSerializers,
          selected: kLayoutSerializers.first,
          onChanged: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    for (final serializer in kLayoutSerializers) {
      expect(find.text(serializer.label), findsOneWidget);
    }
  });

  testWidgets('el panel de métricas dice s/d cuando MLKit no reporta confianza', (
    tester,
  ) async {
    final sinConfianza = OcrResult(
      imageWidth: 800,
      imageHeight: 600,
      blocks: [
        OcrBlock(
          text: 'hola',
          box: const OcrRect(left: 0, top: 0, width: 100, height: 20),
          lines: const [
            OcrLine(
              text: 'hola',
              box: OcrRect(left: 0, top: 0, width: 100, height: 20),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(mount(MeasurePanel(result: sinConfianza, elapsed: null)));

    expect(tester.takeException(), isNull);
    expect(find.text('s/d'), findsOneWidget);
    // Sin medición de tiempo el panel muestra un guión, no un cero engañoso.
    expect(find.text('—'), findsOneWidget);
  });
}
