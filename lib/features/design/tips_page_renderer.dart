import 'dart:convert';

import 'design_page_bridge.dart';
import 'tips_domain_repository.dart';

/// Appends same-home source rows below the packaged demo cards.
/// All strings enter the WebView through textContent.
class TipsPageRenderer {
  const TipsPageRenderer();

  String script(DesignPageTicket ticket, TipsDomainSnapshot snapshot) {
    final payload = jsonEncode({
      'homeId': snapshot.homeId,
      'page': ticket.page,
      'generation': ticket.generation,
      'programs': [
        for (final program in snapshot.programs?.programs ?? const [])
          {
            'id': program.id,
            'title': program.title,
            'administrator': program.administratorName,
            'benefit': program.benefitDisplay,
            'url': program.sourceUrl.toString(),
          },
      ],
      'recommendations': [
        for (final action in snapshot.recommendations)
          {
            'id': '${action.applianceId}/${action.ruleId}',
            'ruleId': action.ruleId,
            'tipCategory': action.tipCategory.name,
            'applianceName':
                snapshot.applianceNames[action.applianceId.toLowerCase()] ?? '',
            'title': action.title,
            'explanation': action.explanation,
          },
      ],
    });
    return '''
(() => {
  const payload = $payload;
  const current = window.__energyLensTextBindingContext;
  if (!current || current.homeId !== payload.homeId ||
      current.page !== payload.page || current.generation !== payload.generation) return false;
  const id = payload.page === 'perks_tips' ? 'el-live-programs' :
    payload.page === 'tips_efficiency' ? 'el-live-tips' : 'el-live-care';
  const mount = document.getElementById(id);
  if (!mount) return false;
  mount.replaceChildren();
  const rows = payload.page === 'perks_tips' ? payload.programs :
    payload.page === 'tips_care_upgrades'
      ? payload.recommendations.filter(row => row.tipCategory === 'care' || row.tipCategory === 'upgrade')
      : payload.recommendations;
  if (!rows.length) return true;
  const heading = document.createElement('h2');
  heading.className = 'text-xs font-bold uppercase tracking-wider text-slate-500 font-label-md';
  heading.textContent = payload.page === 'perks_tips' ? 'Other' : 'For your devices';
  mount.append(heading);
  const list = document.createElement('div');
  list.className = 'flex flex-col gap-space-xs';
  mount.append(list);
  for (const row of rows) {
    const card = document.createElement('article');
    card.className = 'p-space-md rounded-xl bg-surface-container-lowest border border-surface-container-high/80 shadow-sm';
    card.setAttribute('data-el-source-id', row.id);
    const body = payload.page === 'perks_tips' ? document.createElement('a') : document.createElement('div');
    body.className = 'block';
    if (payload.page === 'perks_tips') {
      body.href = row.url;
      body.rel = 'noopener noreferrer';
    }
    const title = document.createElement('h3');
    title.className = 'font-label-md text-label-md text-on-surface font-semibold';
    title.textContent = row.title;
    body.append(title);
    const detail = document.createElement('p');
    detail.className = 'font-body-md text-body-md text-on-surface-variant text-[13px] mt-space-xs';
    detail.textContent = payload.page === 'perks_tips' ? row.administrator : row.explanation;
    if (payload.page !== 'perks_tips' && row.applianceName) {
      const name = document.createElement('p');
      name.className = 'font-body-md text-body-md text-on-surface-variant text-[13px] mt-space-xs';
      name.textContent = row.applianceName;
      body.append(name);
    }
    body.append(detail);
    if (payload.page === 'perks_tips') {
      const benefit = document.createElement('p');
      benefit.className = 'font-body-md text-body-md text-primary font-semibold text-[13px] mt-space-xs';
      benefit.textContent = row.benefit;
      body.append(benefit);
    }
    card.append(body);
    list.append(card);
  }
  return true;
})()
''';
  }
}
