import 'package:flutter/material.dart';

/// Compact host-state readout: player-LED slot dots plus an RGB swatch.
///
/// Values come from `NusClient.lastLedIndex`/`lastRgb`, which track
/// `event led`/`event rgb` lines (pushed by the host and mirrored back by
/// `led?`/`rgb?` queries). Parents rebuild on client notifications already.
class HostStatusStrip extends StatelessWidget {
  final int ledIndex;
  final List<int> rgb;
  const HostStatusStrip({
    super.key,
    required this.ledIndex,
    required this.rgb,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = rgb.isNotEmpty ? rgb[0].clamp(0, 255) : 0;
    final g = rgb.length > 1 ? rgb[1].clamp(0, 255) : 0;
    final b = rgb.length > 2 ? rgb[2].clamp(0, 255) : 0;
    return Row(
      children: [
        const Icon(Icons.lightbulb_outline, size: 16),
        const SizedBox(width: 4),
        for (var i = 1; i <= 4; i++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == ledIndex
                    ? Colors.tealAccent
                    : scheme.surfaceContainerHighest,
                border: Border.all(color: scheme.outlineVariant),
              ),
            ),
          ),
        Text(
          ledIndex > 0 ? 'P$ledIndex' : '—',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(width: 12),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Color.fromARGB(255, r, g, b),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.outlineVariant),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ],
    );
  }
}
