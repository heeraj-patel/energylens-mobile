import 'dart:convert';

import '../../core/cloud_api/cloud_recommendations.dart';
import 'design_page_bridge.dart';
import 'tips_domain_repository.dart';

/// Appends same-home source rows below the packaged demo cards.
/// All strings enter the WebView through textContent.
class TipsPageRenderer {
  const TipsPageRenderer();

  /// Converts an evidence-backed annual USD scenario to the compact monthly
  /// chip used by the packaged Tips examples. Integer arithmetic keeps the
  /// cent rounding stable for every supported six-decimal Cloud amount.
  static String? savingsChipLabel(CloudRecommendation action) {
    final amount = action.savingsAmount;
    if (amount == null ||
        (action.state != 'active' && action.state != 'accepted') ||
        action.savingsPeriod != 'year' ||
        action.savingsCurrency != 'USD' ||
        action.savingsBasis != 'reviewed_action_scenario' ||
        action.scenarioRefs.isEmpty ||
        !RegExp(r'^\d+(?:\.\d{1,6})?$').hasMatch(amount)) {
      return null;
    }

    final parts = amount.split('.');
    final whole = BigInt.parse(parts.first);
    final fraction = parts.length == 1 ? '' : parts[1];
    final micros =
        whole * BigInt.from(1000000) + BigInt.parse(fraction.padRight(6, '0'));
    final monthlyCents = (micros + BigInt.from(60000)) ~/ BigInt.from(120000);
    if (monthlyCents == BigInt.zero) return null;

    if (monthlyCents < BigInt.from(100)) {
      final cents = (monthlyCents % BigInt.from(100)).toString().padLeft(
        2,
        '0',
      );
      return 'Save ~\$0.$cents/mo';
    }
    final monthlyDollars = (monthlyCents + BigInt.from(50)) ~/ BigInt.from(100);
    return 'Save ~\$$monthlyDollars/mo';
  }

  String script(
    DesignPageTicket ticket,
    TipsDomainSnapshot snapshot, {
    DateTime? now,
    Map<String, String> applianceFuels = const {},
  }) {
    final asOf = (now ?? DateTime.now()).toUtc();
    final payload = jsonEncode({
      'homeId': snapshot.homeId,
      'page': ticket.page,
      'generation': ticket.generation,
      'programs': [
        for (final program in snapshot.programs?.programs ?? const [])
          if (program.isCurrentAt(asOf))
            {
              'id': program.id,
              'title': program.title,
              'administrator': program.administratorName,
              'benefit': program.benefitDisplay,
              'url': program.sourceUrl.toString(),
              'expiresAt': program.displayExpiresAt
                  .toUtc()
                  .millisecondsSinceEpoch,
            },
      ],
      'recommendations': [
        for (final action in snapshot.recommendations)
          {
            'id': '${action.applianceId}/${action.ruleId}',
            'applianceId': action.applianceId.toLowerCase(),
            'fuel': applianceFuels[action.applianceId.toLowerCase()],
            'state': action.state,
            'nextQuestion': action.nextQuestion,
            'ruleId': action.ruleId,
            'tipCategory': action.tipCategory.name,
            'applianceName':
                snapshot.applianceNames[action.applianceId.toLowerCase()] ?? '',
            'title': action.title,
            'explanation': action.explanation,
            'monthlySavings': savingsChipLabel(action),
            'sourceUrl': action.sourceUrl?.toString(),
            'researchText': action.researchTip?.sourceText,
            'researchUrl': action.researchTip?.sourceUrl.toString(),
            'researchHost': action.researchTip?.sourceUrl.host,
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
  for (const old of document.querySelectorAll('[data-el-live-examples]')) old.remove();
  const rows = payload.page === 'perks_tips' ? payload.programs.filter(row => Date.now() < row.expiresAt) :
    payload.page === 'tips_care_upgrades'
      ? payload.recommendations.filter(row => row.tipCategory === 'care' || row.tipCategory === 'upgrade')
      : payload.recommendations;
  const notifyTipsChanged = () => {
    if (payload.page !== 'perks_tips') {
      mount.dispatchEvent(new Event('energylens:tips-changed', {bubbles: true}));
    }
  };
  if (!rows.length) {
    notifyTipsChanged();
    return true;
  }
  const headingClass = 'text-xs font-bold uppercase tracking-wider text-slate-500 font-label-md';
  if (payload.page !== 'perks_tips') {
    const fuelLabels = {natural_gas: 'Gas', propane: 'Propane', electricity: 'Electric'};
    const hints = {
      confirm_model: name => 'Add the model number to get advice for this ' + (name || 'appliance') + '.',
      add_gas_rate: () => 'Add your gas rate in Settings to see costs.',
    };
    const yours = document.createElement('h2');
    yours.className = headingClass;
    yours.textContent = 'Your devices';
    mount.append(yours);
    const groups = new Map();
    for (const row of rows) {
      if (!groups.has(row.applianceId)) groups.set(row.applianceId, []);
      groups.get(row.applianceId).push(row);
    }
    for (const [, items] of groups) {
      const first = items[0];
      const group = document.createElement('div');
      group.setAttribute('data-el-tip-group', '');
      group.className = 'flex flex-col gap-space-xs p-space-sm rounded-xl bg-surface-container-low border border-surface-container-high/80 shadow-sm';
      const header = document.createElement('div');
      header.className = 'flex items-center justify-between pb-1 border-b border-surface-container-high/60';
      const label = document.createElement('div');
      label.className = 'flex items-center gap-1.5';
      const icon = document.createElement('span');
      icon.className = 'material-symbols-outlined text-primary text-[18px]';
      icon.textContent = 'devices';
      const applianceTitle = document.createElement('h3');
      applianceTitle.className = 'font-bold tracking-tight text-slate-900 text-[14px]';
      applianceTitle.textContent = first.applianceName;
      label.append(icon, applianceTitle);
      header.append(label);
      const chipText = (items.find(item => item.monthlySavings) || {}).monthlySavings || fuelLabels[first.fuel];
      if (chipText) {
        const chip = document.createElement('span');
        chip.className = 'px-2 py-0.5 rounded-full bg-sky-100 text-sky-800 font-semibold text-[11px]';
        chip.textContent = chipText;
        header.append(chip);
      }
      group.append(header);
      const list = document.createElement('div');
      list.className = 'flex flex-col gap-1.5';
      group.append(list);
      for (const row of items) {
        const card = document.createElement('article');
        card.className = 'p-space-md rounded-xl bg-surface-container-lowest border border-surface-container-high/80 shadow-sm';
        card.setAttribute('data-el-tip-item', '');
        card.setAttribute('data-el-source-id', row.id);
        const body = document.createElement('div');
        body.className = 'block';
        const title = document.createElement('h3');
        title.className = 'font-label-md text-label-md text-on-surface font-semibold';
        if (row.sourceUrl) {
          const link = document.createElement('a');
          link.href = row.sourceUrl;
          link.target = '_blank';
          link.rel = 'noopener noreferrer';
          link.style.color = 'inherit';
          link.style.textDecoration = 'none';
          link.textContent = row.title;
          title.append(link);
        } else {
          title.textContent = row.title;
        }
        body.append(title);
        const detail = document.createElement('p');
        detail.className = 'font-body-md text-body-md text-on-surface-variant text-[13px] mt-space-xs';
        const hint = row.state === 'candidate' && hints[row.nextQuestion];
        detail.textContent = hint ? hint(row.applianceName) : row.explanation;
        body.append(detail);
        if (payload.page === 'tips_care_upgrades' && row.researchText && row.researchUrl) {
          const research = document.createElement('p');
          research.className = 'font-body-md text-body-md text-on-surface-variant text-[13px] mt-space-xs';
          research.setAttribute('data-el-research-source', '');
          research.textContent = '"' + row.researchText + '" (' + row.researchHost + ') ';
          const sourceLink = document.createElement('a');
          sourceLink.href = row.researchUrl;
          sourceLink.target = '_blank';
          sourceLink.rel = 'noopener noreferrer';
          sourceLink.textContent = 'Source';
          research.append(sourceLink);
          body.append(research);
        }
        if (row.monthlySavings) {
          const savings = document.createElement('span');
          savings.className = 'px-2 py-0.5 rounded-full bg-secondary-container el-useful-ink text-[11px] font-semibold flex-shrink-0';
          savings.textContent = row.monthlySavings;
          body.append(savings);
        }
        card.append(body);
        list.append(card);
      }
      mount.append(group);
    }
    const examples = document.createElement('h2');
    examples.className = headingClass;
    examples.setAttribute('data-el-live-examples', '');
    examples.textContent = 'Examples';
    mount.after(examples);
    notifyTipsChanged();
    return true;
  }
  const heading = document.createElement('h2');
  heading.className = headingClass;
  heading.textContent = 'Other';
  mount.append(heading);
  const list = document.createElement('div');
  list.className = 'flex flex-col gap-space-xs';
  mount.append(list);
  const timedCards = [];
  for (const row of rows) {
    const card = document.createElement('article');
    card.className = 'p-space-md rounded-xl bg-surface-container-lowest border border-surface-container-high/80 shadow-sm';
    if (payload.page !== 'perks_tips') card.setAttribute('data-el-tip-item', '');
    card.setAttribute('data-el-source-id', row.id);
    const body = payload.page === 'perks_tips' ? document.createElement('a') : document.createElement('div');
    body.className = 'block';
    if (payload.page === 'perks_tips') {
      body.href = row.url;
      body.rel = 'noopener noreferrer';
    }
    const title = document.createElement('h3');
    title.className = 'font-label-md text-label-md text-on-surface font-semibold';
    if (row.sourceUrl) {
      const link = document.createElement('a');
      link.href = row.sourceUrl;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      link.style.color = 'inherit';
      link.style.textDecoration = 'none';
      link.textContent = row.title;
      title.append(link);
    } else {
      title.textContent = row.title;
    }
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
    if (payload.page !== 'perks_tips' && row.monthlySavings) {
      const savings = document.createElement('span');
      savings.className = 'px-2 py-0.5 rounded-full bg-secondary-container el-useful-ink text-[11px] font-semibold flex-shrink-0';
      savings.textContent = row.monthlySavings;
      body.append(savings);
    }
    if (payload.page === 'perks_tips') {
      const benefit = document.createElement('p');
      benefit.className = 'font-body-md text-body-md text-primary font-semibold text-[13px] mt-space-xs';
      benefit.textContent = row.benefit;
      body.append(benefit);
    }
    card.append(body);
    list.append(card);
    if (payload.page === 'perks_tips') timedCards.push({card, expiresAt: row.expiresAt});
  }
  notifyTipsChanged();
  if (timedCards.length && typeof setTimeout === 'function') {
    const pruneExpired = () => {
      const active = window.__energyLensTextBindingContext;
      if (!active || active.homeId !== payload.homeId ||
          active.page !== payload.page || active.generation !== payload.generation) return;
      const now = Date.now();
      for (const item of timedCards) {
        if (now >= item.expiresAt) item.card.remove();
      }
      const pending = timedCards.filter(item => item.card.isConnected);
      if (!pending.length) {
        heading.remove();
        list.remove();
        return;
      }
      const next = Math.min(...pending.map(item => item.expiresAt));
      setTimeout(pruneExpired, Math.max(0, Math.min(next - now, 86400000)));
    };
    const next = Math.min(...timedCards.map(item => item.expiresAt));
    setTimeout(pruneExpired, Math.max(0, Math.min(next - Date.now(), 86400000)));
  }
  return true;
})()
''';
  }
}
