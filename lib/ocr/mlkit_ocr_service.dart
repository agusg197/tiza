import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'models/ocr_result.dart';
import 'ocr_service.dart';

/// Implementación con MLKit Text Recognition: on-device, gratis, ~decenas de ms.
///
/// Este es el único archivo del proyecto que conoce los tipos de MLKit. Todo lo
/// que sale de acá es [OcrResult], Dart puro.
class MlkitOcrService implements OcrService {
  MlkitOcrService({TextRecognitionScript script = TextRecognitionScript.latin})
    : _recognizer = TextRecognizer(script: script);

  final TextRecognizer _recognizer;

  @override
  Future<OcrResult> recognize(File image) async {
    if (!await image.exists()) {
      throw const OcrException('No se encontró el archivo de la imagen.');
    }

    // El tamaño se lee del header, antes de llamar al OCR: hace falta para
    // normalizar las coordenadas y no depende del reconocedor.
    final size = await _readImageSize(image);

    final RecognizedText recognized;
    try {
      recognized = await _recognizer.processImage(InputImage.fromFile(image));
    } catch (error) {
      throw OcrException('MLKit no pudo procesar la imagen.', cause: error);
    }

    return OcrResult(
      imageWidth: size.width,
      imageHeight: size.height,
      blocks: [
        for (final block in recognized.blocks)
          OcrBlock(
            text: block.text,
            box: _toOcrRect(block.boundingBox),
            lines: [
              for (final line in block.lines)
                OcrLine(
                  text: line.text,
                  box: _toOcrRect(line.boundingBox),
                  confidence: line.confidence,
                ),
            ],
          ),
      ],
    );
  }

  @override
  Future<void> close() => _recognizer.close();

  static OcrRect _toOcrRect(ui.Rect rect) => OcrRect(
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
  );

  /// Lee ancho y alto del header de la imagen sin decodificarla entera: una foto
  /// de 12 MP descomprimida son ~48 MB de RAM que no necesitamos.
  ///
  /// Devuelve `(0, 0)` si el header no se puede leer; los serializadores caen a
  /// normalizar contra el rectángulo del contenido.
  static Future<({int width, int height})> _readImageSize(File image) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(await image.readAsBytes());
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return (width: descriptor.width, height: descriptor.height);
    } catch (_) {
      return (width: 0, height: 0);
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
