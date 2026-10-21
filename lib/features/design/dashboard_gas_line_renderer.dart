import 'dart:convert';

import 'design_page_bridge.dart';

/// Adds or removes the Dashboard gas line (G-C8) at the end of the cost card
/// for the current ticket. The text is assigned with textContent.
class DashboardGasLineRenderer {
  const DashboardGasLineRenderer(this.gate);
  final DesignPageRequestGate gate;

  String? script(DesignPageTicket ticket, String? text) {
    if (!gate.acceptsTicket(ticket) || ticket.page != 'dashboard') return null;
    final payload = base64Encode(
      utf8.encode(
        jsonEncode({
          'context': {
            'homeId': ticket.homeId,
            'page': ticket.page,
            'generation': ticket.generation,
          },
          'text': text,
        }),
      ),
    );
    return '''
(() => {
  const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$payload'), c => c.charCodeAt(0))));
  const current = window.__energyLensTextBindingContext;
  const expected = payload.context;
  if (!current || current.homeId !== expected.homeId || current.page !== expected.page || current.generation !== expected.generation) return false;
  const anchor = document.querySelector('[data-el-bind="dashboard_text_004"]');
  const card = anchor && anchor.closest('.rounded-xl');
  if (!card) return false;
  for (const old of card.querySelectorAll('[data-el-gas-line]')) old.remove();
  if (typeof payload.text !== 'string' || payload.text.length === 0) return true;
  const line = document.createElement('p');
  line.setAttribute('data-el-gas-line', '');
  line.className = 'font-label-md text-label-md text-on-surface-variant';
  line.textContent = payload.text;
  card.appendChild(line);
  return true;
})()
''';
  }
}
