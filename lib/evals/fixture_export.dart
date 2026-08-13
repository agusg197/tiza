import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../ocr/models/ocr_result.dart';

/// Escribe un caso del golden set desde el teléfono.
///
/// Sin esto el paso 7 es teórico: el golden set necesita fotos reales, y el OCR de
/// una foto real sólo existe en el dispositivo. Esto lo congela en disco para que
/// el runner —que corre en la máquina— pueda usarlo.
///
/// Se escribe en el directorio externo de la app, que se puede sacar con `adb pull`
/// sin root y sin permisos especiales:
///
/// ```bash
/// adb pull /sdcard/Android/data/com.agustin.tiza/files/fixtures ./fixtures
/// ```
class FixtureExport {
  const FixtureExport({required this.directory, required this.id});

  final String directory;
  final String id;
}

/// Guarda `ocr.json`, la imagen y una plantilla de `expected.md`.
///
/// La plantilla se deja **vacía a propósito**, con el markdown esperado por
/// escribir. Prellenarla con la respuesta del modelo arruinaría el golden set: se
/// estaría midiendo al modelo contra sí mismo.
Future<FixtureExport> exportFixture({
  required OcrResult result,
  required File image,
  required String serialized,
  DateTime? now,
}) async {
  final base = await getExternalStorageDirectory();
  if (base == null) {
    throw const FileSystemException('No hay almacenamiento externo disponible.');
  }

  final stamp = (now ?? DateTime.now())
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '-')
      .substring(0, 19);
  final id = 'caso-$stamp';

  final folder = Directory('${base.path}/fixtures/$id');
  await folder.create(recursive: true);

  await File('${folder.path}/ocr.json').writeAsString(
    // Con sangría para que el fixture se pueda leer y revisar en el repo, que es
    // donde va a vivir.
    const JsonEncoder.withIndent('  ').convert(result.toJson()),
  );

  await File('${folder.path}/serializado.txt').writeAsString(serialized);

  // Se escriben los bytes en vez de usar `image.copy`. `copy` hereda los permisos
  // del origen, y el archivo que deja el picker en la caché viene como
  // `-rw-------`: el archivo aparece en la carpeta pero `adb pull` falla con
  // "Permission denied", y el flujo documentado para armar el golden set se rompe
  // sin dar ninguna pista. Pasó de verdad.
  await File(
    '${folder.path}/foto${_extensionOf(image.path)}',
  ).writeAsBytes(await image.readAsBytes());

  await File('${folder.path}/expected.md').writeAsString(_template);

  return FixtureExport(directory: folder.path, id: id);
}

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  return dot == -1 ? '.jpg' : path.substring(dot);
}

/// Las líneas que arrancan con `<!--` las ignora el parser del golden set, así que
/// la plantilla puede traer instrucciones sin ensuciar las métricas.
const String _template = '''
<!--
Escribí acá el markdown que DEBERÍA salir de esta foto, mirando la foto y no la
respuesta del modelo. Si se copia la respuesta del modelo, la eval mide al modelo
contra sí mismo y no sirve para nada.

Formato reconocido:
  # Título
  ## Sección
  - bullet
  ## Action items
  - Responsable: la tarea

Mientras este archivo esté vacío, el runner saltea el caso y lo dice.
-->
''';
