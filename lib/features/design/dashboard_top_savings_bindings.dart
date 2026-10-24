import 'dart:convert';

import '../../core/cloud_api/cloud_household_energy.dart';
import '../../core/cloud_api/cloud_top_savings_move.dart';
import 'design_page_bridge.dart';

/// Text values and hidden elements for the Dashboard Top Saving Move card.
class DashboardTopSavingsBindings {
  const DashboardTopSavingsBindings(this.bindings, this.hiddenBindingIds);

  final List<DesignTextBinding> bindings;
  final Set<String> hiddenBindingIds;
}

/// A null response leaves the packaged card untouched.
DashboardTopSavingsBindings? prepareDashboardTopSavingsBindings(
  CloudTopSavingsMove? response,
) {
  if (response == null) return null;
  final move = response.move;
  if (move == null) {
    return const DashboardTopSavingsBindings([
      DesignTextBinding('dashboard_text_015', 'No savings move yet'),
      DesignTextBinding(
        'dashboard_text_016',
        'Add or monitor a device to find one',
      ),
    ], {'dashboard_text_014', 'dashboard_text_018'});
  }
  final detail = move.basis == 'idle_waste'
      ? 'Idle waste • ${_money(move.dailyWaste!)}/day'
      : move.actionTitle!;
  return DashboardTopSavingsBindings([
    DesignTextBinding(
      'dashboard_text_014',
      '${_money(move.monthlySavings)}/mo',
    ),
    DesignTextBinding('dashboard_text_015', move.name),
    DesignTextBinding('dashboard_text_016', detail),
  ], {'dashboard_text_018'});
}

String _money(CloudEnergyMoney value) {
  final amount = double.parse(value.amount).abs().toStringAsFixed(2);
  return value.currency == 'USD' ? '\$$amount' : '${value.currency} $amount';
}

/// Hides the matching dashboard elements for the ticket's current page load.
String hideDashboardBindingsScript(
  DesignPageTicket ticket,
  Set<String> bindingIds,
) {
  final context = jsonEncode({
    'homeId': ticket.homeId,
    'page': ticket.page,
    'generation': ticket.generation,
  });
  return '''
(() => {
  const expected = $context;
  const current = window.__energyLensTextBindingContext;
  if (!current || current.homeId !== expected.homeId || current.page !== expected.page || current.generation !== expected.generation) return false;
  for (const id of ${jsonEncode(bindingIds.toList())}) {
    document.querySelectorAll('[data-el-bind=' + JSON.stringify(id) + ']').forEach(node => {
      node.classList.add('hidden');
      node.hidden = true;
    });
  }
  return true;
})()
''';
}
