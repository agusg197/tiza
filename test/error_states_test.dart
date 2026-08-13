import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiza/llm/llm_client.dart';
import 'package:tiza/llm/structured_note.dart';
import 'package:tiza/theme/tiza_theme.dart';
import 'package:tiza/ui/screen_error.dart';
import 'package:tiza/ui/widgets/error_note.dart';
import 'package:tiza/ui/widgets/no_text_state.dart';

/// El paso 6: que cada fallo se vea y que cada fallo tenga salida.
void main() {
  Widget mount(Widget child) => MaterialApp(
    theme: tizaTheme(Brightness.light),
    home: Scaffold(body: child),
  );

  group('recoveriesFor', () {
    test('ningún fallo queda sin salida', () {
      // Este es el test que importa. El error más fácil de cometer acá es dejar un
      // caso sin acción, y una pantalla de error sin salida es un callejón.
      // Recorre el enum entero, así que también cubre los fallos que se agreguen
      // después de escribir esto.
      for (final failure in LlmFailure.values) {
        expect(
          recoveriesFor(failure),
          isNotEmpty,
          reason: '${failure.name} no ofrece ninguna salida al usuario',
        );
      }
    });

    test('sin key la salida es configurarla, no reintentar', () {
      final recoveries = recoveriesFor(LlmFailure.missingKey);

      expect(recoveries.first, ErrorRecovery.openSettings);
      // Reintentar sin key vuelve a fallar igual: ofrecerlo sería mentirle al
      // usuario sobre lo que va a pasar.
      expect(recoveries, isNot(contains(ErrorRecovery.retry)));
      expect(recoveries, contains(ErrorRecovery.useFake));
    });

    test('un contenido bloqueado no ofrece reintentar', () {
      // Los filtros son deterministas sobre el mismo contenido: reintentar da
      // exactamente el mismo bloqueo. Lo único que cambia el resultado es la foto.
      final recoveries = recoveriesFor(LlmFailure.blocked);

      expect(recoveries, isNot(contains(ErrorRecovery.retry)));
      expect(recoveries, contains(ErrorRecovery.anotherPhoto));
    });

    test('la cuota agotada ofrece esperar o bajar de modelo', () {
      // Los límites del tier gratuito son por modelo, así que cambiar de modelo es
      // una salida real y no un consuelo.
      expect(
        recoveriesFor(LlmFailure.rateLimited),
        containsAll([ErrorRecovery.retry, ErrorRecovery.chooseSmallerModel]),
      );
    });

    test('los fallos transitorios ofrecen reintentar primero', () {
      for (final failure in [
        LlmFailure.network,
        LlmFailure.server,
        LlmFailure.badResponse,
      ]) {
        expect(recoveriesFor(failure).first, ErrorRecovery.retry);
      }
    });
  });

  group('ScreenError.fromLlm', () {
    test('conserva el mensaje y el detalle del proveedor', () {
      final error = ScreenError.fromLlm(
        const LlmException(
          LlmFailure.invalidKey,
          'Google rechazó la API key.',
          detail: 'API key not valid.',
        ),
      );

      expect(error.message, 'Google rechazó la API key.');
      expect(error.detail, 'API key not valid.');
      expect(error.recoveries, [ErrorRecovery.openSettings]);
    });
  });

  group('el JSON que no valida', () {
    test('el error se lleva el texto que llegó, en vez de descartarlo', () {
      // Sin esto el usuario ve "no es JSON" y no tiene con qué entender por qué.
      try {
        parseStructuredNote('{"sections": [ esto no cierra');
        fail('tendría que haber lanzado');
      } on LlmException catch (error) {
        expect(error.failure, LlmFailure.badResponse);
        expect(error.detail, contains('esto no cierra'));
      }
    });

    test('recorta un detalle enorme para que quepa en la nota', () {
      final ruido = 'x' * 5000;
      try {
        parseStructuredNote('no soy json $ruido');
        fail('tendría que haber lanzado');
      } on LlmException catch (error) {
        expect(error.detail!.length, lessThan(400));
        expect(error.detail, endsWith('…'));
      }
    });
  });

  group('ErrorNote', () {
    testWidgets('muestra el mensaje y una acción por salida', (tester) async {
      final tocadas = <ErrorRecovery>[];

      await tester.pumpWidget(
        mount(
          ErrorNote(
            error: const ScreenError(
              message: 'No hay conexión a internet.',
              recoveries: [ErrorRecovery.retry],
            ),
            onRecovery: tocadas.add,
            onDismiss: () {},
          ),
        ),
      );

      expect(find.text('No hay conexión a internet.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      expect(tocadas, [ErrorRecovery.retry]);
    });

    testWidgets('el detalle arranca oculto y se despliega a pedido', (tester) async {
      await tester.pumpWidget(
        mount(
          ErrorNote(
            error: const ScreenError(
              message: 'La API devolvió 400.',
              detail: 'Invalid JSON payload received.',
              recoveries: [ErrorRecovery.retry],
            ),
            onRecovery: (_) {},
            onDismiss: () {},
          ),
        ),
      );

      expect(find.text('Invalid JSON payload received.'), findsNothing);

      await tester.tap(find.text('Ver el detalle'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid JSON payload received.'), findsOneWidget);

      await tester.tap(find.text('Ocultar el detalle'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid JSON payload received.'), findsNothing);
    });

    testWidgets('sin detalle no ofrece desplegarlo', (tester) async {
      await tester.pumpWidget(
        mount(
          ErrorNote(
            error: const ScreenError(
              message: 'Algo pasó.',
              recoveries: [ErrorRecovery.anotherPhoto],
            ),
            onRecovery: (_) {},
            onDismiss: () {},
          ),
        ),
      );

      expect(find.text('Ver el detalle'), findsNothing);
      expect(find.text('Otra foto'), findsOneWidget);
    });
  });

  group('NoTextState', () {
    testWidgets('explica por qué pudo fallar y ofrece sacar otra foto', (
      tester,
    ) async {
      var pedidas = 0;

      await tester.pumpWidget(mount(NoTextState(onAnotherPhoto: () => pedidas++)));

      expect(find.text('No encontré texto en esta foto.'), findsOneWidget);
      // La limitación de MLKit con la cursiva se dice, no se esconde.
      expect(
        find.textContaining('MLKit está entrenado sobre imprenta'),
        findsOneWidget,
      );

      await tester.tap(find.text('Probar con otra foto'));
      expect(pedidas, 1);
    });
  });
}
