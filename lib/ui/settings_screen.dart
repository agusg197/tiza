import 'package:flutter/material.dart';

import '../llm/llm_client.dart';
import '../llm/model_option.dart';
import '../settings/settings_store.dart';
import '../theme/tiza_theme.dart';
import 'decor/paper_grain.dart';

/// Ajustes: la API key y el modelo.
///
/// La key la pone el usuario. Es la única forma de que la app sea gratis para
/// cualquiera —cada uno usa su propio tier gratuito— y de que la key no viva
/// dentro del APK, de donde se puede extraer.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});

  final SettingsStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _controller = TextEditingController();

  String? _savedKeyTail;
  ModelOption _model = kDefaultModel;
  OutputMode _mode = OutputMode.schema;
  bool _obscured = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = await widget.store.readApiKey();
    final model = await widget.store.readModel();
    final mode = await widget.store.readOutputMode();
    if (!mounted) return;
    setState(() {
      _savedKeyTail = _tailOf(key);
      _model = model;
      _mode = mode;
      _loading = false;
    });
  }

  /// Nunca se muestra la key completa, ni siquiera al dueño: alcanza con los
  /// últimos cuatro caracteres para confirmar cuál está guardada.
  static String? _tailOf(String? key) {
    if (key == null || key.isEmpty) return null;
    return key.length <= 4 ? key : key.substring(key.length - 4);
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;

    await widget.store.writeApiKey(value);
    if (!mounted) return;

    setState(() {
      _savedKeyTail = _tailOf(value);
      _controller.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Key guardada en el Keystore del sistema.')),
    );
  }

  Future<void> _delete() async {
    await widget.store.deleteApiKey();
    if (!mounted) return;
    setState(() => _savedKeyTail = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Key borrada.')),
    );
  }

  Future<void> _selectModel(ModelOption model) async {
    setState(() => _model = model);
    await widget.store.writeModel(model);
  }

  Future<void> _selectMode(OutputMode mode) async {
    setState(() => _mode = mode);
    await widget.store.writeOutputMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.tiza;

    return Scaffold(
      body: PaperGrain(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 20, 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      color: palette.ink,
                      tooltip: 'Volver',
                    ),
                    const SizedBox(width: 4),
                    Text('Ajustes', style: theme.textTheme.headlineMedium),
                  ],
                ),
              ),
              Divider(height: 1, color: palette.rule),
              Expanded(
                child: _loading
                    ? const SizedBox.shrink()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                        children: [
                          _SectionTitle('API KEY DE GEMINI'),
                          const SizedBox(height: 10),
                          Text(
                            'La key es tuya y se guarda cifrada en este teléfono. '
                            'No viaja a ningún lado más que a Google.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          if (_savedKeyTail != null) ...[
                            _SavedKeyRow(tail: _savedKeyTail!, onDelete: _delete),
                            const SizedBox(height: 14),
                          ],
                          TextField(
                            controller: _controller,
                            obscureText: _obscured,
                            autocorrect: false,
                            enableSuggestions: false,
                            style: const TextStyle(
                              fontFamily: kMono,
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
                              hintText: _savedKeyTail == null
                                  ? 'Pegá tu key acá'
                                  : 'Pegá una key nueva para reemplazarla',
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => _obscured = !_obscured),
                                icon: Icon(
                                  _obscured
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 19,
                                ),
                                color: palette.inkMuted,
                                tooltip: _obscured ? 'Mostrar' : 'Ocultar',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _save,
                            child: const Text('Guardar'),
                          ),
                          const SizedBox(height: 18),
                          _Note(
                            children: [
                              Text(
                                'Se saca gratis, sin tarjeta, en:',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                'aistudio.google.com/apikey',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: kMono,
                                  color: palette.accent,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Ojo con una cosa: en el tier gratuito Google usa el '
                                'contenido para mejorar sus productos. Acá no sale la '
                                'foto, sale el texto que leyó el OCR — pero el texto '
                                'es justamente la parte sensible. Para un pizarrón de '
                                'trabajo, tenelo en cuenta.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          _SectionTitle('MODELO'),
                          const SizedBox(height: 10),
                          Text(
                            'Sólo los Flash y Flash-Lite, que son los que entran en '
                            'el tier gratuito. Cambiar de modelo es la otra variable '
                            'que se mide, además del formato de serialización.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          _ChoiceGroup(
                            children: [
                              for (final option in kModelOptions)
                                _ChoiceRow(
                                  label: option.label,
                                  note: option.note,
                                  mono: option.apiId,
                                  selected: option.id == _model.id,
                                  onTap: () => _selectModel(option),
                                ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          _SectionTitle('MODO DE SALIDA'),
                          const SizedBox(height: 10),
                          Text(
                            'Cómo se le pide la nota al modelo. Los dos caminos '
                            'conviven porque compararlos es el tercer eje que se '
                            'mide, además del formato y del modelo.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          _ChoiceGroup(
                            children: [
                              for (final option in OutputMode.values)
                                _ChoiceRow(
                                  label: option.label,
                                  note: option.note,
                                  selected: option == _mode,
                                  onTap: () => _selectMode(option),
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.labelSmall);
}

class _SavedKeyRow extends StatelessWidget {
  const _SavedKeyRow({required this.tail, required this.onDelete});

  final String tail;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    return Container(
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 16, color: palette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Hay una key guardada, termina en '),
                  TextSpan(
                    text: '…$tail',
                    style: const TextStyle(fontFamily: kMono),
                  ),
                ],
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.ink,
              ),
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 19),
            color: palette.inkMuted,
            tooltip: 'Borrar la key',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: palette.rule, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// Contenedor de opciones, con los separadores entre filas.
class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.rule),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final child in children) ...[
            if (child != children.first) Divider(height: 1, color: palette.rule),
            child,
          ],
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.note,
    required this.selected,
    required this.onTap,
    this.mono,
  });

  final String label;
  final String note;

  /// Línea monoespaciada opcional al pie: el `apiId` del modelo, por ejemplo.
  final String? mono;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.tiza;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Marca propia en vez de Radio: el Radio de Material trae su color y
            // su área de toque, y desentona sobre el papel.
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? palette.accent : palette.rule,
                  width: selected ? 5 : 1.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(note, style: theme.textTheme.bodySmall),
                  if (mono != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      mono!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: kMono,
                        letterSpacing: 0,
                        color: palette.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
