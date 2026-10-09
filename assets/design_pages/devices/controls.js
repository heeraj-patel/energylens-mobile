(() => {
  const feed = document.getElementById('devices-feed');
  const filters = document.getElementById('status-filter-group');
  const sorts = document.getElementById('sort-pill-group');
  const summary = document.querySelector('[data-el-bind="devices_text_092"]');
  const reveal = document.getElementById('devices-reveal');
  if (!feed || !filters || !sorts || !summary || !reveal) return;

  const action = number => '[data-el-action="devices_action_' + String(number).padStart(3, '0') + '"]';
  const filterActions = {devices_action_004: 'all', devices_action_005: 'active',
    devices_action_006: 'idle', devices_action_007: 'standby'};
  const sortActions = {devices_action_008: 'name', devices_action_009: 'usage',
    devices_action_010: 'waste'};
  let filter = 'all';
  let sort = 'waste';
  let expanded = false;
  const previewCount = 3;

  function money(text) {
    const match = /^\$([0-9]+(?:\.[0-9]+)?)$/.exec(text.trim());
    return match ? Number(match[1]) : null;
  }

  function row(card) {
    if (card.hasAttribute('data-el-live-device-id')) {
      return {card, name: card.getAttribute('data-el-device-name') || '',
        state: null, usage: null, waste: null};
    }
    const fields = Array.from(card.querySelectorAll('[data-el-bind]'));
    const stateText = (fields[2]?.textContent || '').trim().toLowerCase();
    const state = ['active', 'idle', 'standby'].find(value => stateText.startsWith(value)) || null;
    const useful = money(fields[4]?.textContent || '');
    const waste = money(fields[6]?.textContent || '');
    return {card, name: (fields[0]?.textContent || '').trim(), state,
      usage: useful !== null && waste !== null ? useful + waste : null, waste};
  }

  function setCount(number, count) {
    const button = filters.querySelector(action(number));
    if (!button) return;
    let badge = button.querySelector('[data-el-count]') ||
      button.querySelector('[data-el-bind="devices_text_012"], [data-el-bind="devices_text_014"], [data-el-bind="devices_text_016"]');
    if (!badge) {
      badge = document.createElement('span');
      badge.className = 'text-[11px] text-on-surface-variant ml-0.5';
      button.appendChild(badge);
    }
    badge.setAttribute('data-el-count', '');
    badge.textContent = number === 4 ? String(count) : '(' + count + ')';
  }

  function render() {
    const rows = Array.from(feed.children).map(row);
    setCount(4, rows.length);
    for (const [index, state] of ['active', 'idle', 'standby'].entries()) {
      setCount(index + 5, rows.filter(item => item.state === state).length);
    }
    const matches = rows.filter(item => filter === 'all' || item.state === filter);
    matches.sort((a, b) => {
      if (sort !== 'name') {
        const aValue = a[sort];
        const bValue = b[sort];
        if (aValue === null && bValue !== null) return 1;
        if (aValue !== null && bValue === null) return -1;
        if (aValue !== null && bValue !== null && aValue !== bValue) return bValue - aValue;
      }
      return a.name.localeCompare(b.name);
    });
    for (const item of rows) {
      item.card.hidden = true;
      item.card.style.display = 'none';
    }
    for (const item of matches) feed.appendChild(item.card);
    const visibleCount = expanded ? matches.length : Math.min(previewCount, matches.length);
    for (const item of matches.slice(0, visibleCount)) {
      item.card.hidden = false;
      item.card.style.display = '';
    }
    summary.textContent = 'Showing ' + (matches.length ? 1 : 0) + '–' +
      visibleCount + ' of ' + matches.length + ' devices';
    reveal.hidden = matches.length <= previewCount;
    reveal.style.display = reveal.hidden ? 'none' : '';
    reveal.textContent = expanded ? 'Show fewer devices' :
      'Show all ' + matches.length + ' devices';
    reveal.setAttribute('aria-expanded', String(expanded));
  }

  filters.addEventListener('click', event => {
    const selected = filterActions[event.target.closest('button')?.dataset.elAction];
    if (!selected) return;
    filter = selected;
    expanded = false;
    render();
  });
  sorts.addEventListener('click', event => {
    const selected = sortActions[event.target.closest('button')?.dataset.elAction];
    if (!selected) return;
    sort = selected;
    expanded = false;
    render();
  });
  reveal.addEventListener('click', () => {
    expanded = !expanded;
    render();
  });
  feed.addEventListener('energylens:devices-changed', () => {
    expanded = false;
    render();
  });
  render();
})();
