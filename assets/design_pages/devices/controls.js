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

  const pageSize = 10;
  let currentPage = 1;

  function money(text) {
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
    const state = ['active', 'idle', 'standby'].find(value => stateText.startsWith(value)) || null;
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

    const pageCount = Math.max(1, Math.ceil(matches.length / pageSize));
    currentPage = Math.min(Math.max(1, currentPage), pageCount);
    const start = (currentPage - 1) * pageSize;
    const pageRows = matches.slice(start, start + pageSize);
    for (const item of rows) {
      item.card.hidden = true;
      item.card.style.display = 'none';
    }
    for (const item of matches) feed.appendChild(item.card);
    for (const item of pageRows) {
      item.card.hidden = false;
      item.card.style.display = '';
    }

    const first = matches.length ? start + 1 : 0;
    const last = matches.length ? start + pageRows.length : 0;
    summary.textContent = 'Showing ' + first + '–' + last + ' of ' + matches.length + ' devices';
    pagination.hidden = matches.length === 0;
    pagination.style.display = pagination.hidden ? 'none' : '';
    previous.disabled = currentPage === 1;
    next.disabled = currentPage === pageCount;
    previous.setAttribute('aria-label', 'Previous page');
    next.setAttribute('aria-label', 'Next page');

    pageNumbers.replaceChildren();
    const visiblePageCount = Math.min(4, pageCount);
    const firstPage = Math.min(
      Math.max(1, currentPage - Math.floor(visiblePageCount / 2)),
      pageCount - visiblePageCount + 1);
    for (let page = firstPage; page < firstPage + visiblePageCount; page++) {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = String(page);
      button.className = 'w-8 h-8 rounded-lg border flex items-center justify-center font-label-md text-[12px] font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary ' +
        (page === currentPage
          ? 'bg-secondary-container border-secondary-container text-on-secondary-container'
          : 'bg-surface-container-lowest border-outline-variant/60 text-on-surface');
      button.setAttribute('aria-label', 'Page ' + page);
      button.setAttribute('aria-controls', 'devices-feed');
      if (page === currentPage) button.setAttribute('aria-current', 'page');
      button.addEventListener('click', () => {
        currentPage = page;
        render();
      });
      pageNumbers.appendChild(button);
    }
  }

  filterSelect.addEventListener('change', () => {
    currentPage = 1;
    render();
  });
  sortSelect.addEventListener('change', () => {
    currentPage = 1;
    render();
  });
  previous.addEventListener('click', () => {
    currentPage--;
    render();
  });
  next.addEventListener('click', () => {
    currentPage++;
    render();
  });
  feed.addEventListener('energylens:devices-changed', () => {
    currentPage = 1;
    render();
  });
  render();
})();
