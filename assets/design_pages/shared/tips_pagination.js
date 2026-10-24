(() => {
  const feed = document.getElementById('tab-panel-efficiency') ||
    document.getElementById('tab-panel-upgrades');
  const footer = document.getElementById('tips-pagination-footer');
  const summary = document.getElementById('tips-pagination-summary');
  const pagination = document.getElementById('tips-pagination');
  const pageNumbers = document.getElementById('tips-page-numbers');
  const previous = document.getElementById('tips-previous-page');
  const next = document.getElementById('tips-next-page');
  if (!feed || !footer || !summary || !pagination || !pageNumbers ||
      !previous || !next) return;

  previous.setAttribute('aria-controls', feed.id);
  next.setAttribute('aria-controls', feed.id);
  const pager = window.EnergyLensListPagination({
    summary, pagination, pageNumbers, previous, next, feedId: feed.id,
    formatSummary: (first, last, total) =>
      'Showing ' + first + '–' + last + ' of ' + total,
    showControls: total => total > 10,
    onPageChange: render,
  });

  function render() {
    const items = Array.from(feed.querySelectorAll('[data-el-tip-item]'));
    const visible = new Set(pager.render(items));
    for (const item of items) {
      item.hidden = !visible.has(item);
      item.style.display = item.hidden ? 'none' : '';
    }
    for (const group of feed.querySelectorAll('[data-el-tip-group]')) {
      const groupItems = Array.from(group.querySelectorAll('[data-el-tip-item]'));
      const hasVisibleItem = groupItems.some(item => visible.has(item));
      const hasEmptyNotice = Boolean(group.querySelector('[data-el-empty-articles]'));
      group.hidden = groupItems.length > 0 ? !hasVisibleItem : !hasEmptyNotice;
      group.style.display = group.hidden ? 'none' : '';
    }
    footer.hidden = items.length <= 10;
    footer.style.display = footer.hidden ? 'none' : '';
  }

  feed.addEventListener('energylens:tips-changed', () => {
    pager.reset();
    render();
  });
  render();
})();
