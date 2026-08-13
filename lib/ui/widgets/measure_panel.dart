import 'package:flutter/material.dart';

import '../../llm/llm_client.dart';
import '../../llm/model_option.dart';
import '../../ocr/models/ocr_result.dart';
import '../../theme/tiza_theme.dart';

/// Las métricas del OCR, tratadas como un instrumento de medición.
///
/// Está arriba en la pantalla y no al pie a propósito. La tesis del proyecto es
/// que el trabajo caro se evita midiendo; estos números son la evidencia de que
/// el camino barato alcanza. Al pie serían decoración.
///
/// Va **separado** de [ModelPanel] por la misma razón: dos paneles distintos
/// dicen que hay dos caminos con costos distintos. Fusionarlos en una sola grilla
/// borraría justo la distinción que el proyecto quiere mostrar.
class MeasurePanel extends StatelessWidget {
  const MeasurePanel({super.key, required this.result, required this.elapsed});

  final OcrResult result;
  final Duration? elapsed;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    final confidence = result.averageConfidence;

    return _PanelShell(
      children: [
        _MeasureRow(
          children: [
            _Measure(
              label: 'OCR',
              value: elapsed == null ? '—' : '${elapsed!.inMilliseconds}',
              unit: elapsed == null ? null : 'ms',
            ),
            _Measure(label: 'RENGLONES', value: '${result.lines.length}'),
            _Measure(
              label: 'CONFIANZA',
              value: confidence == null ? 's/d' : '${(confidence * 100).round()}',
              unit: confidence == null ? null : '%',
              // La confianza es lo único que puede dar mala noticia, así que es
              // lo único que se pinta.
              emphasized: confidence != null && confidence < 0.7,
            ),
          ],
        ),
        Divider(height: 1, color: palette.rule),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              Text(
                'on-device · ${result.blocks.length} bloques',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              if (result.imageWidth > 0)
                Text(
                  '${result.imageWidth}×${result.imageHeight}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: kMono,
                    letterSpacing: 0,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Lo que costó la llamada al modelo.
///
/// Los tokens salen del `usageMetadata` de la respuesta, no de una estimación por
/// caracteres: es el número que se factura. Tenerlo al lado de las métricas
/// gratuitas es todo el argumento del proyecto en una pantalla.
class ModelPanel extends StatelessWidget {
  const ModelPanel({super.key, required this.reply, required this.model});

  final ModelReply reply;
  final ModelOption model;

  @override
  Widget build(BuildContext context) {
    final tokens = reply.promptTokens == null || reply.outputTokens == null
        ? 's/d'
        : '${reply.promptTokens}→${reply.outputTokens}';

    return _PanelShell(
      children: [
        _MeasureRow(
          children: [
            _Measure(
              label: 'MODELO',
              value: model.label,
              // El nombre del modelo es texto, no una cifra: al tamaño de las
              // otras métricas se desborda de la columna.
              valueFontSize: 14,
            ),
            _Measure(label: 'TOKENS', value: tokens),
            _Measure(
              label: 'LATENCIA',
              value: '${reply.elapsed.inMilliseconds}',
              unit: 'ms',
            ),
          ],
        ),
        // Las dos malas noticias que puede traer una respuesta. Van al pie del
        // panel de métricas, no en el texto, porque son medidas: el paso 7 las va
        // a contar por foto.
        if (reply.truncated)
          _Footnote(
            icon: Icons.warning_amber_rounded,
            // Una nota cortada a la mitad se ve igual de prolija que una completa.
            // Si el modelo no terminó, hay que decirlo.
            text: 'Respuesta incompleta (${reply.finishReason})',
          ),
        if (reply.warnings.isNotEmpty)
          _Footnote(
            icon: Icons.filter_alt_outlined,
            text: '${reply.warnings.length} '
                '${reply.warnings.length == 1 ? "entrada descartada" : "entradas descartadas"} '
                'por validación',
          ),
      ],
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    return Column(
      children: [
        Divider(height: 1, color: palette.rule),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            spacing: 6,
            children: [
              Icon(icon, size: 14, color: palette.accent),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.children});

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
      child: Column(children: children),
    );
  }
}

/// Fila de métricas con separadores verticales.
///
/// El `IntrinsicHeight` no es opcional: estos paneles son hijos no flexibles de
/// una Column, que les pasa altura sin límite, y `CrossAxisAlignment.stretch`
/// contra infinito hace fallar el layout de todo el subárbol sin lanzar una
/// excepción visible — la pantalla simplemente se dibuja en blanco. Está cubierto
/// por los tests de `test/layout_test.dart`.
class _MeasureRow extends StatelessWidget {
  const _MeasureRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children) ...[
            if (child != children.first) Container(width: 1, color: palette.rule),
            Expanded(child: child),
          ],
        ],
      ),
    );
  }
}

class _Measure extends StatelessWidget {
  const _Measure({
    required this.label,
    required this.value,
    this.unit,
    this.emphasized = false,
    this.valueFontSize = 20,
  });

  final String label;
  final String value;
  final String? unit;
  final bool emphasized;
  final double valueFontSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    final color = emphasized ? palette.accent : palette.ink;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: kMono,
                    fontSize: valueFontSize,
                    fontWeight: FontWeight.w600,
                    color: color,
                    height: 1,
                  ),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(
                  unit!,
                  style: TextStyle(
                    fontFamily: kMono,
                    fontSize: 11,
                    color: palette.inkMuted,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
