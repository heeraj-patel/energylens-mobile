// One visual treatment for the chrome shared by every approved mobile page.
(() => {
  'use strict';

  // Tablet styles apply only on tablet-sized windows of a screen at least 600px on both sides.
  const tabletSheet = document.createElement('link');
  tabletSheet.rel = 'stylesheet';
  tabletSheet.media = '(min-width: 700px) and (min-device-width: 600px) and (min-device-height: 600px)';
  tabletSheet.href = new URL('tablet_layout.css', document.currentScript.src).href;
  document.head.appendChild(tabletSheet);

  const destinations = ['dashboard', 'devices', 'efficiency', 'perks-and-tips', 'settings'];
  const selectedDestination = {
    dashboard: 'dashboard', devices: 'devices', efficiency: 'efficiency',
    tips: 'perks-and-tips', settings: 'settings',
  };
  const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[character]);

  const renderHeader = (config) => {
    // Dashboard's home switcher is a native route; the other pages bind an action.
    const homeAction = config.activeTab === 'dashboard'
      ? `data-el-route="${escapeHtml(config.homeRoute || 'change_home')}"`
      : `data-el-action="${escapeHtml(config.headerActions[0])}"`;
    const profileAction = config.headerActions[config.activeTab === 'dashboard' ? 0 : 1];
    return `<header class="fixed top-0 w-full z-50 el-app-header"><div class="pt-safe"><div class="h-16 px-gutter flex items-center justify-between"><div class="flex items-center gap-space-sm"><div class="w-11 h-11 flex items-center justify-center rounded-xl el-app-header-icon"><span class="material-symbols-outlined text-[22px]">${escapeHtml(config.leadingIcon)}</span></div><div class="flex flex-col"><button class="flex items-center gap-space-xs text-left group" type="button" ${homeAction}><span class="font-label-md text-label-md text-on-surface tracking-tight font-semibold" data-el-bind="${escapeHtml(config.headerBindings[0])}">${escapeHtml(config.homeName)}</span><span class="material-symbols-outlined text-on-surface-variant text-[18px] transition-transform group-hover:translate-y-0.5">expand_more</span></button><span class="text-[11px] leading-tight text-on-surface-variant font-label-md tracking-wider uppercase" data-el-bind="${escapeHtml(config.headerBindings[1])}">${escapeHtml(config.pageLabel)}</span></div></div><div class="flex items-center gap-space-sm"><a class="w-11 h-11 flex items-center justify-center" data-path="settings" href="#" data-el-action="${escapeHtml(profileAction)}"><img alt="Profile" class="w-8 h-8 rounded-full object-cover el-app-profile" src="${escapeHtml(config.profileImage)}"></a></div></div></div></header>`;
  };

  const renderFooter = (config) => {
    const tabs = destinations.map((destination, index) => {
      const active = destination === selectedDestination[config.activeTab];
      const current = active ? ' aria-current="page"' : '';
      const tabClass = 'el-app-tab flex flex-col items-center justify-center w-14 h-12 gap-0.5';
      const iconClass = 'el-app-tab-icon material-symbols-outlined text-[22px]';
      const labelClass = 'el-app-tab-label text-xs leading-none tracking-tight';
      return `<a${current} class="${tabClass}" data-path="${destination}" href="#" data-el-action="${escapeHtml(config.footerActions[index])}"><span class="${iconClass}" aria-hidden="true">${escapeHtml(config.tabIcons[index])}</span><span class="${labelClass}" data-el-bind="${escapeHtml(config.footerBindings[index])}">${escapeHtml(config.tabLabels[index])}</span></a>`;
    }).join('');
    return `<nav class="fixed bottom-0 w-full z-50 pb-safe el-app-nav"><div class="flex justify-around items-center h-16 px-space-xs">${tabs}</div></nav>`;
  };

  const mount = (config) => {
    const expectedHeaderActions = config.activeTab === 'dashboard' ? 1 : 2;
    if (!(config.activeTab in selectedDestination) ||
        config.headerBindings.length !== 2 ||
        config.headerActions.length !== expectedHeaderActions ||
        config.footerBindings.length !== 5 ||
        config.footerActions.length !== 5 ||
        config.tabIcons.length !== 5 ||
        config.tabLabels.length !== 5) {
      throw new Error('Invalid design chrome configuration');
    }
    document.body.dataset.elTab = config.activeTab;
    document.body.dataset.elPage = config.headerBindings[0].replace(/_text_\d+$/, '');
    document.getElementById('el-header').outerHTML = renderHeader(config);
    document.getElementById('el-footer').outerHTML = renderFooter(config);
  };

  window.EnergyLensChrome = Object.freeze({ mount });

  // Moves the selected look to the clicked category pill within its own group.
  window.selectTypePill = (pill) => {
    const group = pill.closest('[role="group"]') || pill.parentElement;
    const on = ['bg-primary-container', 'text-on-primary-container', 'font-semibold'];
    const off = ['bg-surface-container-low', 'text-on-surface-variant', 'hover:text-on-surface'];
    group.querySelectorAll('.type-pill').forEach((item) => {
      const selected = item === pill;
      item.classList.remove(...(selected ? off : on));
      item.classList.add(...(selected ? on : off));
    });
  };
})();
