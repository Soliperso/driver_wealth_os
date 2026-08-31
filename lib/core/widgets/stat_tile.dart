import 'package:flutter/material.dart';

import '../format/money.dart';

/// How much weight a [StatTile] carries.
enum StatEmphasis {
  /// A supporting figure in a row of three.
  normal,

  /// The one number the card is about.
  strong,

  /// A reference figure in a dense grid, sitting deliberately below a headline
  /// number on the same card. Six tiles at [normal] weight compete with the
  /// figure they are supposed to be supporting.
  compact,
}

/// A label over a figure.
///
/// History, the hero card and the weekly panel each grew their own copy of this
/// with slightly different padding and type ramps, which is why the same metric
/// looked subtly different depending on which card it appeared in.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = StatEmphasis.normal,
    this.valueColor,
    this.padding = const EdgeInsets.only(right: 8),
  });

  final String label;
  final String value;
  final StatEmphasis emphasis;
  final Color? valueColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final compact = emphasis == StatEmphasis.compact;
    final style =
        switch (emphasis) {
          StatEmphasis.strong => textTheme.titleLarge,
          StatEmphasis.normal => textTheme.titleMedium,
          StatEmphasis.compact => textTheme.titleSmall,
        }?.copyWith(
          fontWeight: compact ? FontWeight.w700 : FontWeight.w800,
          color: valueColor,
          fontFeatures: tabularFigures,
        );

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // Small caps and a little tracking let the label read as a caption
            // rather than as another line of content competing with the figure.
            compact ? label.toUpperCase() : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: compact
                ? textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    letterSpacing: .5,
                    fontWeight: FontWeight.w600,
                  )
                : textTheme.bodySmall,
          ),
          SizedBox(height: compact ? 3 : 5),
          // Long figures shrink rather than wrap, so a row of three tiles keeps
          // its baseline no matter how big the numbers get.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: style),
          ),
        ],
      ),
    );
  }
}
