import 'package:flutter/material.dart';

/// A compact table of precomputed daily costs for a home's devices.
class PowerNowDailyCostTable extends StatelessWidget {
  const PowerNowDailyCostTable({super.key, required this.rows});

  final List<PowerNowDailyCostRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.4),
        1: FlexColumnWidth(1.15),
        2: FlexColumnWidth(1.15),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            _cell(
              'Device',
              style: headerStyle,
              alignment: Alignment.centerLeft,
            ),
            _cell(
              'Used today',
              style: headerStyle,
              alignment: Alignment.centerRight,
            ),
            _cell(
              'Wasted today',
              style: headerStyle,
              alignment: Alignment.centerRight,
            ),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.deviceName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (row.plugName != null && row.plugName!.trim().isNotEmpty)
                      Text(
                        row.plugName!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              _cell(
                _formatCost(row.usedTodayUsd),
                alignment: Alignment.centerRight,
              ),
              _cell(
                _formatCost(row.wastedTodayUsd),
                alignment: Alignment.centerRight,
              ),
            ],
          ),
      ],
    );
  }

  static Widget _cell(
    String text, {
    TextStyle? style,
    required Alignment alignment,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
    child: Align(
      alignment: alignment,
      child: Text(text, style: style, textAlign: TextAlign.end),
    ),
  );

  static String _formatCost(double? value) =>
      value == null ? 'N/A' : '\$${value.toStringAsFixed(2)}';
}

/// One device row. Costs are supplied by the caller and are not calculated here.
class PowerNowDailyCostRow {
  const PowerNowDailyCostRow({
    required this.deviceName,
    this.plugName,
    required this.usedTodayUsd,
    required this.wastedTodayUsd,
  });

  final String deviceName;
  final String? plugName;
  final double? usedTodayUsd;
  final double? wastedTodayUsd;
}
