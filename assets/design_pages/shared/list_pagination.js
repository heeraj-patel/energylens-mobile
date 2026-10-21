window.EnergyLensListPagination = function ({summary, pagination, pageNumbers,
    previous, next, feedId, formatSummary, showControls, onPageChange}) {
  const pageSize = 10;
  let currentPage = 1;

  function render(items) {
    const pageCount = Math.max(1, Math.ceil(items.length / pageSize));
    currentPage = Math.min(Math.max(1, currentPage), pageCount);
    const start = (currentPage - 1) * pageSize;
    const pageItems = items.slice(start, start + pageSize);
    const first = items.length ? start + 1 : 0;
    const last = items.length ? start + pageItems.length : 0;
    summary.textContent = formatSummary(first, last, items.length);
    pagination.hidden = !showControls(items.length);
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
      button.setAttribute('aria-controls', feedId);
      if (page === currentPage) button.setAttribute('aria-current', 'page');
      button.addEventListener('click', () => { currentPage = page; onPageChange(); });
      pageNumbers.appendChild(button);
    }
    return pageItems;
  }

  previous.addEventListener('click', () => { currentPage--; onPageChange(); });
  next.addEventListener('click', () => { currentPage++; onPageChange(); });
  return {render, reset: () => { currentPage = 1; }};
};
