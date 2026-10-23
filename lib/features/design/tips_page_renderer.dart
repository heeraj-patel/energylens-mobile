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

  static const _weatherChips = {
    'heat_alert': 'Heat alert',
    'cold_alert': 'Cold alert',
    'hot_run': 'Hot spell',
    'cold_run': 'Cold spell',
  };
  static const peakDemandTitle = 'Peak demand days';
  static const peakDemandNotice =
      'Austin Energy tells selected customers about Peak Energy Demand Days '
      'by email, text or call. EnergyLens cannot see which days they are.';
  static const peakDemandWindow =
      'On those days, Austin Energy asks customers to save energy from 1 to 7 pm.';
  static const peakDemandChip = 'Peak demand day';
  static const eccAttribution =
      'Data Source: Environment and Climate Change Canada';
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String? weatherChip(CloudWeatherContext? context) =>
      context == null ? null : _weatherChips[context.trigger];

  static String _clock12(String hhmm) {
    final hour = int.parse(hhmm.substring(0, 2));
    final minute = hhmm.substring(3);
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h${minute == '00' ? '' : ':$minute'} ${hour < 12 ? 'AM' : 'PM'}';
  }

  /// Per-kWh time-of-use line; null unless Cloud sent the whole cost group.
  static String? weatherCostLine(CloudWeatherContext? context) {
    final amount = context?.touSavingPerKwh;
    final start = context?.peakStartLocal;
    final end = context?.peakEndLocal;
    if (amount == null || start == null || end == null) return null;
    final parts = amount.split('.');
    final fraction =
        (parts.length == 1 ? '' : parts[1].replaceFirst(RegExp(r'0+$'), ''))
            .padRight(2, '0');
    return 'On your plan, each kWh moved out of '
        '${_clock12(start)}-${_clock12(end)} saves \$${parts.first}.$fraction.';
  }

  /// Event is provider text; only its first letter is capitalised.
  static String weatherAlertLine(CloudWeatherAlert alert) {
    final event = alert.event.trim();
    final name = event[0].toUpperCase() + event.substring(1);
    final end = alert.endsAt.toLocal();
    final hour = end.hour % 12 == 0 ? 12 : end.hour % 12;
    final minute = end.minute.toString().padLeft(2, '0');
    final when =
        '${_months[end.month - 1]} ${end.day}, $hour:$minute '
        '${end.hour < 12 ? 'AM' : 'PM'}';
    return '$name until $when';
  }

  /// Card data for the Efficiency page; null shows no weather UI. Alert lines
  /// only appear next to home tips, so they are dropped without them.
  static Map<String, Object?>? _weatherPayload(CloudWeather? weather) {
    if (weather == null || !weather.available || weather.homeTips.isEmpty) {
      return null;
    }
    return {
      'tips': [
        for (final row in weather.homeTips)
          {
            'text': row.tip.sourceText,
            'url': row.tip.sourceUrl.toString(),
            'host': row.tip.sourceUrl.host,
          },
      ],
      'alerts': [
        for (final alert in weather.alerts)
          {'line': weatherAlertLine(alert), 'url': alert.sourceUrl.toString()},
      ],
      'attribution': weather.provider == 'eccc' && weather.alerts.isNotEmpty
          ? eccAttribution
          : null,
    };
  }

  static Map<String, Object?>? _peakDemandPayload(CloudPeakDemand? peak) {
    if (peak == null) return null;
    return {
      'title': peakDemandTitle,
      'notice': peakDemandNotice,
      'window': peakDemandWindow,
      'tips': [
        for (final tip in peak.homeTips)
          {
            'text': tip.sourceText,
            'url': tip.sourceUrl.toString(),
            'host': tip.sourceUrl.host,
          },
      ],
    };
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
      'weather': ticket.page == 'tips_efficiency'
          ? _weatherPayload(snapshot.weather)
          : null,
      'peakDemand': ticket.page == 'tips_efficiency'
          ? _peakDemandPayload(snapshot.peakDemand)
          : null,
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
            'isWeather': action.weatherContext != null,
            'weatherChip': weatherChip(action.weatherContext),
            'weatherCost': weatherCostLine(action.weatherContext),
            'peakChip': action.peakDemandContext == null
                ? null
                : peakDemandChip,
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
  const headingClass = 'text-xs font-bold uppercase tracking-wider text-slate-500 font-label-md';
  const detailClass = 'font-body-md text-body-md text-on-surface-variant text-[13px] mt-space-xs';
  const researchRow = (text, host, url) => {
    const research = document.createElement('p');
    research.className = detailClass;
    research.setAttribute('data-el-research-source', '');
    research.textContent = '"' + text + '" (' + host + ') ';
    const sourceLink = document.createElement('a');
    sourceLink.href = url;
    sourceLink.target = '_blank';
    sourceLink.rel = 'noopener noreferrer';
    sourceLink.textContent = 'Source';
    research.append(sourceLink);
    return research;
  };
  if (payload.page === 'tips_efficiency' && payload.weather) {
    const group = document.createElement('div');
    group.setAttribute('data-el-tip-group', '');
    group.setAttribute('data-el-weather-card', '');
    group.className = 'flex flex-col gap-space-xs p-space-sm rounded-xl bg-surface-container-low border border-surface-container-high/80 shadow-sm';
    const header = document.createElement('div');
    header.className = 'flex items-center justify-between pb-1 border-b border-surface-container-high/60';
    const label = document.createElement('div');
    label.className = 'flex items-center gap-1.5';
    const icon = document.createElement('span');
    icon.className = 'material-symbols-outlined text-primary text-[18px]';
    icon.textContent = 'home';
    const homeTitle = document.createElement('h3');
    homeTitle.className = 'font-bold tracking-tight text-slate-900 text-[14px]';
    homeTitle.textContent = 'Your home';
    label.append(icon, homeTitle);
    header.append(label);
    group.append(header);
    for (const alert of payload.weather.alerts) {
      const line = document.createElement('p');
      line.className = detailClass;
      line.setAttribute('data-el-weather-alert', '');
      line.textContent = alert.line + ' ';
      const alertLink = document.createElement('a');
      alertLink.href = alert.url;
      alertLink.target = '_blank';
      alertLink.rel = 'noopener noreferrer';
      alertLink.textContent = 'Source';
      line.append(alertLink);
      group.append(line);
    }
    if (payload.weather.attribution) {
      const credit = document.createElement('p');
      credit.className = 'font-body-md text-body-md text-on-surface-variant text-[11px]';
      credit.setAttribute('data-el-weather-attribution', '');
      credit.textContent = payload.weather.attribution;
      group.append(credit);
    }
    const tipList = document.createElement('div');
    tipList.className = 'flex flex-col gap-1.5';
    payload.weather.tips.forEach((tip, index) => {
      const card = document.createElement('article');
      card.className = 'p-space-md rounded-xl bg-surface-container-lowest border border-surface-container-high/80 shadow-sm';
      card.setAttribute('data-el-tip-item', '');
      card.setAttribute('data-el-source-id', 'weather/home/' + index);
      const body = document.createElement('div');
      body.className = 'block';
      body.append(researchRow(tip.text, tip.host, tip.url));
      card.append(body);
      tipList.append(card);
    });
    group.append(tipList);
    mount.append(group);
  }
  if (payload.page === 'tips_efficiency' && payload.peakDemand) {
    const group = document.createElement('div');
    group.setAttribute('data-el-tip-group', '');
    group.setAttribute('data-el-peak-demand-card', '');
    group.className = 'flex flex-col gap-space-xs p-space-sm rounded-xl bg-surface-container-low border border-surface-container-high/80 shadow-sm';
    const header = document.createElement('div');
    header.className = 'flex items-center justify-between pb-1 border-b border-surface-container-high/60';
    const label = document.createElement('div');
    label.className = 'flex items-center gap-1.5';
    const icon = document.createElement('span');
    icon.className = 'material-symbols-outlined text-primary text-[18px]';
    icon.textContent = 'home';
    const peakTitle = document.createElement('h3');
    peakTitle.className = 'font-bold tracking-tight text-slate-900 text-[14px]';
    peakTitle.textContent = payload.peakDemand.title;
    label.append(icon, peakTitle);
    header.append(label);
    group.append(header);
    for (const text of [payload.peakDemand.notice, payload.peakDemand.window]) {
      const line = document.createElement('p');
      line.className = detailClass;
      line.setAttribute('data-el-peak-demand-line', '');
      line.textContent = text;
      group.append(line);
    }
    const tipList = document.createElement('div');
    tipList.className = 'flex flex-col gap-1.5';
    payload.peakDemand.tips.forEach((tip, index) => {
      const card = document.createElement('article');
      card.className = 'p-space-md rounded-xl bg-surface-container-lowest border border-surface-container-high/80 shadow-sm';
      card.setAttribute('data-el-tip-item', '');
      card.setAttribute('data-el-source-id', 'peak_demand/home/' + index);
      const body = document.createElement('div');
      body.className = 'block';
      body.append(researchRow(tip.text, tip.host, tip.url));
      card.append(body);
      tipList.append(card);
    });
    group.append(tipList);
    mount.append(group);
  }
  if (!rows.length) {
    notifyTipsChanged();
    return true;
  }
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
        if (row.weatherChip) {
          const trigger = document.createElement('span');
          trigger.className = 'px-2 py-0.5 rounded-full bg-sky-100 text-sky-800 font-semibold text-[11px]';
          trigger.setAttribute('data-el-weather-trigger', '');
          trigger.textContent = row.weatherChip;
          body.append(trigger);
        }
        if (row.peakChip) {
          const peak = document.createElement('span');
          peak.className = 'px-2 py-0.5 rounded-full bg-sky-100 text-sky-800 font-semibold text-[11px]';
          peak.setAttribute('data-el-peak-demand-trigger', '');
          peak.textContent = row.peakChip;
          body.append(peak);
        }
        if (row.weatherCost) {
          const cost = document.createElement('p');
          cost.className = detailClass;
          cost.setAttribute('data-el-weather-cost', '');
          cost.textContent = row.weatherCost;
          body.append(cost);
        }
        if ((payload.page === 'tips_care_upgrades' || row.isWeather || row.peakChip) && row.researchText && row.researchUrl) {
          body.append(researchRow(row.researchText, row.researchHost, row.researchUrl));
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
