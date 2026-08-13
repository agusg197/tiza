import '../llm/llm_client.dart';

/// Las salidas que se le pueden ofrecer al usuario cuando algo falla.
enum ErrorRecovery {
  /// Volver a intentar la misma llamada.
  retry,

  /// Ir a los ajustes a poner o corregir la key.
  openSettings,

  /// Recorrer la pantalla con una respuesta simulada, sin red ni key.
  useFake,

  /// Ir a los ajustes a bajar de modelo.
  chooseSmallerModel,

  /// Sacar otra foto.
  anotherPhoto,
}

/// Qué puede hacer el usuario ante cada tipo de fallo.
///
/// Es una función pura, separada de los widgets, por una razón concreta: el error
/// que más fácil se comete acá es dejar un fallo **sin ninguna salida**, y una
/// pantalla de error sin acción es un callejón. Siendo pura, hay un test que
/// recorre todos los casos de [LlmFailure] y falla si alguno queda sin recovery —
/// incluidos los que se agreguen después.
List<ErrorRecovery> recoveriesFor(LlmFailure failure) => switch (failure) {
  // Sin key no hay nada que reintentar: hay que configurarla. El fake está para
  // poder ver la pantalla igual.
  LlmFailure.missingKey => const [
    ErrorRecovery.openSettings,
    ErrorRecovery.useFake,
  ],
  LlmFailure.invalidKey => const [ErrorRecovery.openSettings],

  // La cuota se recupera esperando, pero bajar de modelo también sirve porque los
  // límites del tier gratuito son por modelo.
  LlmFailure.rateLimited => const [
    ErrorRecovery.retry,
    ErrorRecovery.chooseSmallerModel,
  ],

  LlmFailure.network => const [ErrorRecovery.retry],
  LlmFailure.server => const [ErrorRecovery.retry],

  // Reintentar el mismo contenido va a dar el mismo filtro. Lo único que cambia
  // el resultado es cambiar la foto.
  LlmFailure.blocked => const [ErrorRecovery.anotherPhoto],

  // Una respuesta mal formada suele ser un tropiezo del modelo, no algo
  // determinista: el mismo pedido de nuevo normalmente sale bien.
  LlmFailure.badResponse => const [ErrorRecovery.retry],
};

/// Un fallo, ya traducido a lo que la pantalla necesita mostrar.
class ScreenError {
  const ScreenError({
    required this.message,
    this.detail,
    this.recoveries = const [],
  });

  ScreenError.fromLlm(LlmException error)
    : message = error.message,
      detail = error.detail,
      recoveries = recoveriesFor(error.failure);

  /// Mensaje en el idioma de la app, sin jerga del proveedor.
  final String message;

  /// Lo que dijo el proveedor, o el texto que devolvió el modelo. Se muestra sólo
  /// si el usuario lo pide: es información de diagnóstico, no de producto.
  final String? detail;

  final List<ErrorRecovery> recoveries;
}
