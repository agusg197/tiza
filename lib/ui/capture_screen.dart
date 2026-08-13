import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../evals/fixture_export.dart';
import '../llm/fake_llm_client.dart';
import '../llm/gemini_client.dart';
import '../llm/llm_client.dart';
import '../llm/model_option.dart';
import '../ocr/mlkit_ocr_service.dart';
import '../ocr/models/ocr_result.dart';
import '../ocr/ocr_service.dart';
import '../serialization/layout_serializer.dart';
import '../settings/settings_store.dart';
import '../theme/tiza_theme.dart';
import 'decor/chalk_sketch.dart';
import 'decor/paper_grain.dart';
import 'screen_error.dart';
import 'settings_screen.dart';
import 'widgets/error_note.dart';
import 'widgets/measure_panel.dart';
import 'widgets/no_text_state.dart';
import 'widgets/output_panel.dart';
import 'widgets/serializer_toggle.dart';

/// Pantalla única: foto → OCR on-device → serialización → modelo.
///
/// El orden de arriba hacia abajo es el del pipeline, y no es casual: el panel
/// gratuito va antes que el caro, y la llamada al modelo es una acción explícita
/// que el usuario dispara. Nada sale del teléfono sin que se toque ese botón.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  final OcrService _ocr = MlkitOcrService();
  final SettingsStore _settings = const SettingsStore();

  File? _image;
  OcrResult? _result;
  Duration? _elapsed;

  ScreenError? _error;

  /// Qué reintentar cuando el usuario toca "Reintentar".
  ///
  /// Se guarda al lanzar la llamada en vez de reconstruirse en el handler, así el
  /// reintento repite exactamente lo que falló —el mismo camino, real o simulado—
  /// y no algo parecido.
  VoidCallback? _retry;

  bool _busy = false;
  bool _asking = false;

  // Arranca en el serializador con coordenadas porque es el que importa; el de
  // texto plano está a un toque de distancia para comparar.
  LayoutSerializer _serializer = kLayoutSerializers.last;
  ModelOption _model = kDefaultModel;
  OutputMode _mode = OutputMode.schema;

  /// Respuestas por combinación de serializador, modelo y modo de salida.
  ///
  /// Cachear no es prematuro: la app existe para comparar esas tres variables, así
  /// que ir y volver entre combinaciones es el gesto más frecuente que hay, y sin
  /// esto cada vuelta paga tokens de nuevo por una entrada idéntica.
  final Map<String, ModelReply> _replies = {};

  OutputTab _tab = OutputTab.input;
  ReplyView _replyView = ReplyView.structure;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _ocr.close();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final model = await _settings.readModel();
    final mode = await _settings.readOutputMode();
    if (!mounted) return;
    setState(() {
      _model = model;
      _mode = mode;
    });
  }

  String get _cacheKey => '${_serializer.id}/${_model.id}/${_mode.name}';
  ModelReply? get _currentReply => _replies[_cacheKey];

  String? get _serializedText {
    final result = _result;
    if (result == null) return null;
    return _serializer.serialize(result);
  }

  void _clearError() => setState(() => _error = null);

  void _showError(ScreenError error) {
    setState(() {
      _error = error;
      _asking = false;
      _busy = false;
    });
  }

  void _handleRecovery(ErrorRecovery recovery) {
    _clearError();
    switch (recovery) {
      case ErrorRecovery.retry:
        _retry?.call();
      case ErrorRecovery.openSettings:
      case ErrorRecovery.chooseSmallerModel:
        _openSettings();
      case ErrorRecovery.useFake:
        _runFake();
      case ErrorRecovery.anotherPhoto:
        _pickSource();
    }
  }

  Future<void> _openSettings() async {
    _clearError();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(store: _settings)),
    );
    // El modelo o el modo pudieron cambiar: se recargan y con eso cambia también
    // la clave de caché, así que el visor pasa a reflejar la combinación nueva.
    await _loadSettings();
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final picked = await _picker.pickImage(source: source);
      if (picked == null) {
        // Cancelado por el usuario: no es un error, se deja todo como estaba.
        if (mounted) setState(() => _busy = false);
        return;
      }

      final file = File(picked.path);
      final stopwatch = Stopwatch()..start();
      final result = await _ocr.recognize(file);
      stopwatch.stop();

      if (!mounted) return;
      setState(() {
        _image = file;
        _result = result;
        _elapsed = stopwatch.elapsed;
        _busy = false;
        _tab = OutputTab.input;
        // Foto nueva: todas las respuestas guardadas corresponden a la anterior.
        _replies.clear();
      });
    } on OcrException catch (error) {
      _showError(
        ScreenError(
          message: error.message,
          detail: error.cause?.toString(),
          recoveries: const [ErrorRecovery.anotherPhoto],
        ),
      );
    } catch (error) {
      _showError(
        ScreenError(
          message: 'No se pudo abrir la imagen.',
          detail: error.toString(),
          recoveries: const [ErrorRecovery.anotherPhoto],
        ),
      );
    }
  }

  Future<void> _runModel() async {
    final serialized = _serializedText;
    if (serialized == null || serialized.isEmpty) return;

    final apiKey = await _settings.readApiKey();
    if (apiKey == null) {
      // Se arma como LlmException y no a mano para que las salidas salgan del
      // mismo mapeo que el resto de los fallos, y no de una lista aparte.
      _showError(
        ScreenError.fromLlm(
          const LlmException(
            LlmFailure.missingKey,
            'Para llamar al modelo hace falta una API key de Gemini. Se saca '
                'gratis en AI Studio y se guarda cifrada en el teléfono.',
          ),
        ),
      );
      return;
    }

    _retry = _runModel;
    await _ask(GeminiClient(apiKey: apiKey), serialized, closeAfter: true);
  }

  /// Recorre el mismo camino con una respuesta simulada, sin red ni key.
  ///
  /// Sirve para ver la pantalla completa antes de tener una key. Está etiquetada
  /// como simulada en el panel del modelo: mostrar un resultado inventado sin
  /// decirlo sería exactamente el problema que este proyecto trata de medir.
  Future<void> _runFake() async {
    final serialized = _serializedText;
    if (serialized == null || serialized.isEmpty) return;
    _retry = _runFake;
    await _ask(const FakeLlmClient(), serialized);
  }

  Future<void> _ask(
    LlmClient client,
    String serialized, {
    bool closeAfter = false,
  }) async {
    setState(() {
      _asking = true;
      _error = null;
      _tab = OutputTab.reply;
      _replyView = ReplyView.structure;
    });

    try {
      final reply = switch (_mode) {
        OutputMode.schema => await client.structureNote(
          serializedOcr: serialized,
          model: _model,
        ),
        OutputMode.freeMarkdown => await client.writeMarkdown(
          serializedOcr: serialized,
          model: _model,
        ),
      };
      if (!mounted) return;
      setState(() {
        _replies[_cacheKey] = reply;
        _asking = false;
      });
    } on LlmException catch (error) {
      if (!mounted) return;
      // Se vuelve a la pestaña de entrada: dejar visible la de respuesta cuando no
      // hay respuesta muestra un panel vacío al lado del error.
      setState(() => _tab = OutputTab.input);
      _showError(ScreenError.fromLlm(error));
    } catch (error) {
      if (!mounted) return;
      setState(() => _tab = OutputTab.input);
      _showError(
        ScreenError(
          message: 'Falló la llamada al modelo.',
          detail: error.toString(),
          recoveries: const [ErrorRecovery.retry],
        ),
      );
    } finally {
      if (closeAfter && client is GeminiClient) client.close();
    }
  }

  Future<void> _copyVisible() async {
    final text = _tab == OutputTab.reply
        ? _currentReply?.markdown
        : _serializedText;
    if (text == null || text.isEmpty) return;

    // Se copia el texto crudo, no lo que se ve: los colores del visor son
    // decoración y no forman parte de lo que recibe el modelo ni de lo que
    // devolvió.
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tab == OutputTab.reply
              ? 'Markdown copiado.'
              : 'Serialización copiada.',
        ),
      ),
    );
  }

  /// Congela esta foto como caso del golden set del paso 7.
  ///
  /// Está en la pestaña de entrada y no en la de respuesta a propósito: lo que se
  /// guarda es el OCR, que es la entrada de la eval. La respuesta del modelo no se
  /// guarda — el markdown esperado lo escribe una persona mirando la foto.
  Future<void> _exportFixture() async {
    final result = _result;
    final image = _image;
    final serialized = _serializedText;
    if (result == null || image == null || serialized == null) return;

    try {
      final export = await exportFixture(
        result: result,
        image: image,
        serialized: serialized,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fixture guardado: ${export.id}'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error) {
      _showError(
        ScreenError(
          message: 'No se pudo guardar el fixture.',
          detail: error.toString(),
          recoveries: const [ErrorRecovery.retry],
        ),
      );
    }
  }

  Future<void> _pickSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.tiza.paper,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Cámara'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.collections_outlined),
              title: const Text('Galería'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) await _pickAndRecognize(source);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PaperGrain(
        child: SafeArea(
          child: Column(
            children: [
              _Header(onSettings: _openSettings),
              _ProgressRule(busy: _busy),
              if (_error != null)
                ErrorNote(
                  error: _error!,
                  onRecovery: _handleRecovery,
                  onDismiss: _clearError,
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOut,
                  child: _result == null
                      ? const _EmptyState(key: ValueKey('empty'))
                      : KeyedSubtree(
                          key: const ValueKey('result'),
                          child: _buildResult(context),
                        ),
                ),
              ),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final result = _result!;
    final reply = _currentReply;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_image != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _Photo(file: _image!),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: MeasurePanel(result: result, elapsed: _elapsed),
        ),
        // El OCR corrió y no encontró nada: no hay qué serializar ni qué
        // preguntarle al modelo, así que el resto de los controles no aparece.
        // El panel de arriba queda, porque 0 renglones es el dato.
        if (result.isEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: NoTextState(onAnotherPhoto: _pickSource),
            ),
          )
        else ...[
          if (reply != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: ModelPanel(reply: reply, model: _model),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SerializerToggle(
              serializers: kLayoutSerializers,
              selected: _serializer,
              onChanged: (serializer) => setState(() => _serializer = serializer),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: OutputPanel(
                tab: _tab,
                onTabChanged: (tab) => setState(() => _tab = tab),
                serialized: _serializedText ?? '',
                serializerDescription: _serializer.description,
                reply: reply,
                asking: _asking,
                replyView: _replyView,
                onReplyViewChanged: (view) => setState(() => _replyView = view),
                onExportFixture: _exportFixture,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    final hasText = _result != null && !_result!.isEmpty;

    if (_result == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(
          spacing: 10,
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _pickAndRecognize(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 19),
                label: const Text('Cámara'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _pickAndRecognize(ImageSource.gallery),
                icon: const Icon(Icons.collections_outlined, size: 19),
                label: const Text('Galería'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final busy = _busy || _asking;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: busy || !hasText ? null : _runModel,
              icon: const Icon(Icons.auto_awesome_outlined, size: 19),
              label: Text(
                _currentReply == null ? 'Estructurar' : 'Preguntar de nuevo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          _SquareAction(
            icon: Icons.add_a_photo_outlined,
            tooltip: 'Otra foto',
            onPressed: busy ? null : _pickSource,
          ),
          _SquareAction(
            icon: Icons.content_copy_outlined,
            tooltip: _tab == OutputTab.reply
                ? 'Copiar el markdown'
                : 'Copiar la serialización',
            onPressed: busy || !hasText ? null : _copyVisible,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.tiza;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tiza', style: theme.textTheme.displaySmall),
                const SizedBox(height: 3),
                Text('de la tiza al markdown', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const _OnDevicePill(),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.tune, size: 21),
            color: palette.inkMuted,
            tooltip: 'Ajustes',
          ),
        ],
      ),
    );
  }
}

/// Píldora de estado. Está acá porque la decisión de arquitectura del proyecto
/// —el OCR no sale del teléfono— merece estar visible en la pantalla y no sólo en
/// el README.
class _OnDevicePill extends StatelessWidget {
  const _OnDevicePill();

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: palette.accent,
              shape: BoxShape.circle,
            ),
          ),
          Text(
            'OCR local',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// La regla bajo el encabezado, que se vuelve barra de progreso mientras trabaja.
/// Reutilizar el separador evita que la pantalla salte de alto al empezar a
/// cargar.
class _ProgressRule extends StatelessWidget {
  const _ProgressRule({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    return SizedBox(
      height: 2,
      child: busy
          ? LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: palette.rule,
              color: palette.accent,
            )
          : ColoredBox(color: palette.rule),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const ChalkSketch(),
            const SizedBox(height: 30),
            Text(
              'El pizarrón, en limpio.',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Sacale una foto a un pizarrón o a una hoja escrita a mano. '
              'El OCR corre acá adentro y no cuesta nada; al modelo se le '
              'pregunta después, y sólo si vos lo pedís.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.rule),
      ),
      clipBehavior: Clip.antiAlias,
      // `contain` y no `cover`: un pizarrón fotografiado es casi cuadrado y esta
      // tira es apaisada y baja, así que recortar deja a la vista justo la parte
      // vacía. Con `contain` se ve la foto entera, apoyada sobre el papel.
      child: Image.file(file, fit: BoxFit.contain, width: double.infinity),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(50, 50),
          fixedSize: const Size(50, 50),
        ),
        child: Icon(icon, size: 19),
      ),
    );
  }
}
