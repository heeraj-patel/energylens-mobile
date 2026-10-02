import 'package:flutter/material.dart';

/// Shows a cost split between useful, waste, and unclassified energy.
class UsefulWasteCostPanel extends StatelessWidget {
  const UsefulWasteCostPanel({
    super.key,
    required this.scopeLabel,
    required this.periodLabel,
    required this.usefulCostUsd,
    required this.wasteCostUsd,
    required this.unclassifiedCostUsd,
    required this.detail,
  });

  final String scopeLabel;
  final String periodLabel;
  final double? usefulCostUsd;
  final double? wasteCostUsd;
  final double? unclassifiedCostUsd;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(scopeLabel, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(periodLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            _CostRow(label: 'Useful cost', amountUsd: usefulCostUsd),
            _CostRow(label: 'Waste cost', amountUsd: wasteCostUsd),
            _CostRow(
              label: 'Unclassified cost',
              amountUsd: unclassifiedCostUsd,
            ),
            const SizedBox(height: 8),
            Text(detail, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow({required this.label, required this.amountUsd});

  final String label;
  final double? amountUsd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            amountUsd == null
                ? 'Unavailable'
                : '\$${amountUsd!.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}
