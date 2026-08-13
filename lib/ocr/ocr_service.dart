import 'dart:io';

import 'models/ocr_result.dart';

/// Reconocimiento de texto sobre una imagen.
///
/// Es una interfaz para que MLKit quede en un solo archivo y sea reemplazable:
/// el paso 7 va a necesitar una implementación que lea fixtures desde el disco
/// para correr las evals sin dispositivo.
abstract class OcrService {
  Future<OcrResult> recognize(File image);

  /// Libera el reconocedor nativo.
  Future<void> close();
}

/// Falla del OCR con un mensaje ya listo para mostrar.
class OcrException implements Exception {
  const OcrException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'OcrException: $message${cause == null ? '' : ' ($cause)'}';
}
