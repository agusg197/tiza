import 'package:flutter/material.dart';

import '../../serialization/layout_serializer.dart';
import '../../theme/tiza_theme.dart';

/// Selector de formato de serialización.
///
/// No usa `SegmentedButton` porque el de Material trae su propio radio de esquina
/// y su propio relleno, y sobre una superficie de papel se lee como un control
/// pegado encima. Este es una pestaña subrayada: el subrayado en terracota es la
/// única parte que se mueve.
class SerializerToggle extends StatelessWidget {
  const SerializerToggle({
    super.key,
    required this.serializers,
    required this.selected,
    required this.onChanged,
  });

  final List<LayoutSerializer> serializers;
  final LayoutSerializer selected;
  final ValueChanged<LayoutSerializer> onChanged;

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
      // Igual que en MeasurePanel: sin IntrinsicHeight, `stretch` se estira
      // contra la altura infinita que le pasa la Column de arriba y el layout
      // falla.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final serializer in serializers) ...[
              if (serializer != serializers.first)
                Container(width: 1, color: palette.rule),
              Expanded(
                child: _Tab(
                  label: serializer.label,
                  selected: serializer.id == selected.id,
                  onTap: () => onChanged(serializer),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? palette.accentSoft : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: selected ? palette.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? palette.ink : palette.inkMuted,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}
