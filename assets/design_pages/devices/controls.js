(() => {
  const feed = document.getElementById('devices-feed');
  const filterSelect = document.getElementById('status-filter-select');
  const sortSelect = document.getElementById('sort-select');
  const summary = document.querySelector('[data-el-bind="devices_text_092"]');
  const pagination = document.getElementById('devices-pagination');
  const pageNumbers = document.getElementById('devices-page-numbers');
  const previous = document.getElementById('devices-previous-page');
  const next = document.getElementById('devices-next-page');
  if (!feed || !filterSelect || !sortSelect || !summary || !pagination ||
      !pageNumbers || !previous || !next) return;

  const pager = window.EnergyLensListPagination({
    summary, pagination, pageNumbers, previous, next, feedId: 'devices-feed',
    formatSummary: (first, last, total) =>
      'Showing ' + first + '–' + last + ' of ' + total + ' devices',
    showControls: total => total > 0,
    onPageChange: render,
  });

  function money(text) {
    if (text.trim() === '<$0.01') return 0.005;
    const match = /^\$([0-9]+(?:\.[0-9]+)?)$/.exec(text.trim());
    return match ? Number(match[1]) : null;
  }

  function row(card) {
    if (card.hasAttribute('data-el-live-device-id') ||
        card.hasAttribute('data-el-seeded-device-id')) {
      return {card, name: card.getAttribute('data-el-device-name') || '',
        state: card.getAttribute('data-el-device-state'),
        usage: money(card.getAttribute('data-el-usage-cost') || ''),
        waste: money(card.getAttribute('data-el-waste-cost') || '')};
    }
    const fields = Array.from(card.querySelectorAll('[data-el-bind]'));
    const stateText = (fields[2]?.textContent || '').trim().toLowerCase();
    const state = ['active', 'idle', 'offline', 'standalone'].find(value => stateText.startsWith(value)) || null;
    const useful = money(fields[4]?.textContent || '');
    const waste = money(fields[6]?.textContent || '');
    return {card, name: (fields[0]?.textContent || '').trim(), state,
      usage: useful !== null && waste !== null ? useful + waste : null, waste};
  }

  function render() {
    const rows = Array.from(feed.children).map(row);
    const filter = filterSelect.value || 'all';
    const sort = sortSelect.value || 'waste';
    const matches = rows.filter(item => filter === 'all' || item.state === filter);
    matches.sort((a, b) => {
      if (sort !== 'name') {
        const aValue = a[sort];
        const bValue = b[sort];
        if (aValue === null && bValue !== null) return 1;
        if (aValue !== null && bValue === null) return -1;
        if (aValue !== null && bValue !== null && aValue !== bValue) return bValue - aValue;
      }
      return a.name.localeCompare(b.name) ||
        (a.card.getAttribute('data-el-live-device-id') ||
          a.card.getAttribute('data-el-seeded-device-id') || '').localeCompare(
          b.card.getAttribute('data-el-live-device-id') ||
          b.card.getAttribute('data-el-seeded-device-id') || '');
    });

    const pageRows = pager.render(matches);
    for (const item of rows) {
      item.card.hidden = true;
      item.card.style.display = 'none';
    }
    for (const item of matches) feed.appendChild(item.card);
    for (const item of pageRows) {
      item.card.hidden = false;
      item.card.style.display = '';
    }

  }

  filterSelect.addEventListener('change', () => {
    pager.reset();
    render();
  });
  sortSelect.addEventListener('change', () => {
    pager.reset();
    render();
  });
  feed.addEventListener('energylens:devices-changed', () => {
    pager.reset();
    render();
  });
  render();
})();
