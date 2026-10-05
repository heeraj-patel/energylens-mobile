import 'package:flutter/material.dart';

/// A compact table of precomputed daily costs for a home's devices.
class PowerNowDailyCostTable extends StatefulWidget {
  const PowerNowDailyCostTable({super.key, required this.rows, this.onRemove});

  final List<PowerNowDailyCostRow> rows;
  final ValueChanged<int>? onRemove;

  @override
  State<PowerNowDailyCostTable> createState() => _PowerNowDailyCostTableState();
}

class _PowerNowDailyCostTableState extends State<PowerNowDailyCostTable> {
  final Set<int> _selectedIds = {};
  bool _selecting = false;

  void _applySelection() {
    final callback = widget.onRemove;
    if (callback == null || _selectedIds.isEmpty) return;
    for (final id in _selectedIds.toList()) {
      callback(id);
    }
    setState(() {
      _selectedIds.clear();
      _selecting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    final table = Table(
      columnWidths: const {
        0: FlexColumnWidth(2.4),
        1: FlexColumnWidth(1.15),
        2: FlexColumnWidth(1.15),
        3: FixedColumnWidth(32),
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
            const SizedBox.shrink(),
          ],
        ),
        for (final row in widget.rows)
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
              _costCell(row),
              _cell(
                _formatCost(row.wastedTodayUsd),
                alignment: Alignment.centerRight,
              ),
              if (widget.onRemove == null || row.applianceId == null)
                const SizedBox.shrink()
              else if (_selecting)
                Checkbox(
                  key: Key('power-now-select-${row.applianceId}'),
                  value: _selectedIds.contains(row.applianceId),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (selected) => setState(() {
                    if (selected == true) {
                      _selectedIds.add(row.applianceId!);
                    } else {
                      _selectedIds.remove(row.applianceId);
                    }
                  }),
                  semanticLabel: row.deviceName,
                )
              else
                const SizedBox.shrink(),
            ],
          ),
      ],
    );

    if (widget.onRemove == null ||
        !widget.rows.any((row) => row.applianceId != null)) {
      return table;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        table,
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            key: const Key('power-now-selection-action'),
            onPressed: _selecting
                ? (_selectedIds.isEmpty ? null : _applySelection)
                : () => setState(() => _selecting = true),
            icon: Icon(
              _selecting ? Icons.check : Icons.remove,
              semanticLabel: _selecting ? 'Apply' : 'Remove',
            ),
            iconSize: 17,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          ),
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

  static Widget _costCell(PowerNowDailyCostRow row) {
    final amount = Text(_formatCost(row.usedTodayUsd));
    if (row.usedTodayUsd == null || row.sourceName == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Align(alignment: Alignment.centerRight, child: amount),
      );
    }
    final details = [
      row.sourceName!,
      if (row.sourceUrl case final url? when url.isNotEmpty) url,
    ].join('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      child: Align(
        alignment: Alignment.centerRight,
        child: Tooltip(
          message: details,
          triggerMode: TooltipTriggerMode.tap,
          child: amount,
        ),
      ),
    );
  }

  static String _formatCost(double? value) =>
      value == null ? 'N/A' : '\$${value.toStringAsFixed(2)}';
}

/// One device row. Costs are supplied by the caller and are not calculated here.
class PowerNowDailyCostRow {
  const PowerNowDailyCostRow({
    this.applianceId,
    required this.deviceName,
    this.plugName,
    this.sourceName,
    this.sourceUrl,
    this.meteredTodayUsd,
    this.meterCoverageFraction,
    required this.usedTodayUsd,
    required this.wastedTodayUsd,
  });

  final int? applianceId;
  final String deviceName;
  final String? plugName;
  final String? sourceName;
  final String? sourceUrl;

  /// Calendar-day meter data reserved for the approved display policy.
  final double? meteredTodayUsd;
  final double? meterCoverageFraction;
  final double? usedTodayUsd;
  final double? wastedTodayUsd;
}
