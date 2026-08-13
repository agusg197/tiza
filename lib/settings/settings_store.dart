import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/llm_client.dart';
import '../llm/model_option.dart';

/// Las preferencias de la app, separadas por sensibilidad.
///
/// La key va a [FlutterSecureStorage], que en Android cifra con RSA OAEP + AES-GCM
/// respaldado por el Keystore. El modelo elegido va a `SharedPreferences`: no es
/// secreto, y guardarlo en almacenamiento cifrado sería decir que sí lo es.
///
/// El motivo de fondo de que la key la ponga el usuario: una key compilada dentro
/// del APK se puede extraer del binario, así que embebida no protege nada. De paso,
/// cada usuario usa su propio tier gratuito.
class SettingsStore {
  const SettingsStore();

  static const String _apiKeyEntry = 'gemini_api_key';
  static const String _modelEntry = 'selected_model_id';
  static const String _outputModeEntry = 'output_mode';

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  Future<String?> readApiKey() async {
    final value = await _secure.read(key: _apiKeyEntry);
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<void> writeApiKey(String value) =>
      _secure.write(key: _apiKeyEntry, value: value.trim());

  Future<void> deleteApiKey() => _secure.delete(key: _apiKeyEntry);

  Future<ModelOption> readModel() async {
    final prefs = await SharedPreferences.getInstance();
    // modelById cae al modelo por defecto si el id guardado ya no existe, que es
    // lo que pasa cuando el proveedor retira un modelo entre dos versiones.
    return modelById(prefs.getString(_modelEntry));
  }

  Future<void> writeModel(ModelOption model) async {
    final prefs = await SharedPreferences.getInstance();
    // Se guarda el id estable, no el apiId: si Google renombra el modelo, la
    // preferencia del usuario sobrevive.
    await prefs.setString(_modelEntry, model.id);
  }

  Future<OutputMode> readOutputMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_outputModeEntry);
    return OutputMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => OutputMode.schema,
    );
  }

  Future<void> writeOutputMode(OutputMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_outputModeEntry, mode.name);
  }
}
