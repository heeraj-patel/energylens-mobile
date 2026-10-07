// Shared approved DesignShell chrome. Section variants preserve source-page styling.
(() => {
  'use strict';
  const variants = {
  "dashboard": {
    "header": "<header class=\"fixed top-0 w-full z-50 bg-surface/90 backdrop-blur-xl border-b border-surface-container-highest/60 shadow-[0_2px_12px_rgba(17,27,47,0.06)]\"><div class=\"pt-safe\"><div class=\"h-16 px-gutter flex items-center justify-between\"><div class=\"flex items-center gap-space-sm\"><div class=\"w-11 h-11 flex items-center justify-center rounded-xl bg-secondary-container/50 text-primary border border-primary-container/40\"><span class=\"material-symbols-outlined text-[22px]\">bolt</span></div><div class=\"flex flex-col\"><button class=\"flex items-center gap-space-xs text-left group\" type=\"button\" data-el-route=\"change_home\"><span class=\"font-label-md text-label-md text-on-surface tracking-tight font-semibold\" data-el-bind=\"{{headerBinding0}}\">The Miller Home</span><span class=\"material-symbols-outlined text-on-surface-variant text-[18px] transition-transform group-hover:translate-y-0.5\">expand_more</span></button><span class=\"text-[11px] leading-tight text-on-surface-variant font-label-md tracking-wider uppercase\" data-el-bind=\"{{headerBinding1}}\">Dashboard</span></div></div><div class=\"flex items-center gap-space-sm\"><a class=\"w-11 h-11 flex items-center justify-center\" data-path=\"settings\" href=\"#\" data-el-action=\"{{headerAction0}}\"><img alt=\"Profile\" class=\"w-8 h-8 rounded-full object-cover ring-2 ring-primary-container\" src=\"../shared/images/image-3.jpg\"></a></div></div></div></header>"
  },
  "devices": {
    "header": "<header class=\"fixed top-0 w-full z-50 bg-surface/90 backdrop-blur-xl border-b border-surface-container-high/60 shadow-sm\"><div class=\"pt-safe\"><div class=\"h-16 px-gutter flex items-center justify-between\"><div class=\"flex items-center gap-space-sm\"><div class=\"w-11 h-11 flex items-center justify-center rounded-xl bg-primary-container text-on-primary-container shadow-xs\"><span class=\"material-symbols-outlined text-[22px]\">bolt</span></div><div class=\"flex flex-col\"><button class=\"flex items-center gap-space-xs text-left group\" type=\"button\" data-el-action=\"{{headerAction0}}\"><span class=\"font-label-md text-label-md text-on-surface tracking-tight font-semibold\" data-el-bind=\"{{headerBinding0}}\">The Miller Home</span><span class=\"material-symbols-outlined text-on-surface-variant text-[18px] transition-transform group-hover:translate-y-0.5\">expand_more</span></button><span class=\"text-[11px] leading-tight text-on-surface-variant font-label-md tracking-wider uppercase\" data-el-bind=\"{{headerBinding1}}\">Devices</span></div></div><div class=\"flex items-center gap-space-sm\"><a class=\"w-11 h-11 flex items-center justify-center\" data-path=\"settings\" href=\"#\" data-el-action=\"{{headerAction1}}\"><img alt=\"Profile\" class=\"w-8 h-8 rounded-full object-cover ring-2 ring-primary/40 shadow-xs\" src=\"../shared/images/image-3.jpg\"></a></div></div></div></header>"
  },
  "efficiency": {
    "header": "<header class=\"fixed top-0 w-full z-50 bg-surface/85 backdrop-blur-xl border-b border-surface-variant/40 shadow-sm\">\n<div class=\"pt-safe\">\n<div class=\"h-16 px-gutter flex items-center justify-between\">\n<div class=\"flex items-center gap-space-sm\">\n<div class=\"w-11 h-11 flex items-center justify-center rounded-xl bg-surface-container-high text-primary shadow-xs\">\n<span class=\"material-symbols-outlined text-[22px]\">bolt</span>\n</div>\n<div class=\"flex flex-col\">\n<button class=\"flex items-center gap-space-xs text-left group\" type=\"button\" data-el-action=\"{{headerAction0}}\">\n<span class=\"font-label-md text-label-md text-on-surface tracking-tight font-semibold\" data-el-bind=\"{{headerBinding0}}\">The Miller Home</span>\n<span class=\"material-symbols-outlined text-on-surface-variant text-[18px] transition-transform group-hover:translate-y-0.5\">expand_more</span>\n</button>\n<span class=\"text-[11px] leading-tight text-on-surface-variant font-label-md tracking-wider uppercase\" data-el-bind=\"{{headerBinding1}}\">Efficiency</span>\n</div>\n</div>\n<div class=\"flex items-center gap-space-sm\">\n\n<a class=\"w-11 h-11 flex items-center justify-center\" data-path=\"settings\" href=\"#\" data-el-action=\"{{headerAction1}}\">\n<img alt=\"Profile\" class=\"w-8 h-8 rounded-full object-cover ring-1 ring-primary/40\" src=\"../shared/images/image-3.jpg\">\n</a>\n</div>\n</div>\n</div>\n</header>"
  },
  "tips": {
    "header": "<header class=\"fixed top-0 w-full z-50 bg-surface/90 backdrop-blur-xl border-b border-surface-container-high/60 shadow-[0_2px_12px_rgba(0,0,0,0.04)]\"><div class=\"pt-safe\"><div class=\"h-16 px-gutter flex items-center justify-between\"><div class=\"flex items-center gap-space-sm\"><div class=\"w-11 h-11 flex items-center justify-center rounded-xl bg-surface-container text-primary\"><span class=\"material-symbols-outlined text-[22px]\">bolt</span></div><div class=\"flex flex-col\"><button class=\"flex items-center gap-space-xs text-left group\" type=\"button\" data-el-action=\"{{headerAction0}}\"><span class=\"font-label-md text-label-md text-on-surface tracking-tight font-semibold\" data-el-bind=\"{{headerBinding0}}\">The Miller Home</span><span class=\"material-symbols-outlined text-on-surface-variant text-[18px] transition-transform group-hover:translate-y-0.5\">expand_more</span></button><span class=\"text-[11px] leading-tight text-on-surface-variant font-label-md tracking-wider uppercase\" data-el-bind=\"{{headerBinding1}}\">Perks And Tips</span></div></div><div class=\"flex items-center gap-space-sm\"><a class=\"w-11 h-11 flex items-center justify-center\" data-path=\"settings\" href=\"#\" data-el-action=\"{{headerAction1}}\"><img alt=\"Profile\" class=\"w-8 h-8 rounded-full object-cover ring-2 ring-primary-container\" src=\"../shared/images/image-3.jpg\"></a></div></div></div></header>"
  },
  "settings": {
    "header": "<header class=\"fixed top-0 w-full z-50 bg-surface/90 backdrop-blur-xl border-b border-surface-container-high/60 shadow-[0_2px_12px_rgba(0,0,0,0.04)]\"><div class=\"pt-safe\"><div class=\"h-16 px-gutter flex items-center justify-between\"><div class=\"flex items-center gap-space-sm\"><div class=\"w-11 h-11 flex items-center justify-center rounded-xl bg-surface-container text-primary border border-outline-variant/30\"><span class=\"material-symbols-outlined text-[22px]\">bolt</span></div><div class=\"flex flex-col\"><button class=\"flex items-center gap-space-xs text-left group\" type=\"button\" data-el-action=\"{{headerAction0}}\"><span class=\"font-label-md text-label-md text-on-surface tracking-tight font-semibold\" data-el-bind=\"{{headerBinding0}}\">The Miller Home</span><span class=\"material-symbols-outlined text-on-surface-variant text-[18px] transition-transform group-hover:translate-y-0.5\">expand_more</span></button><span class=\"text-[11px] leading-tight text-on-surface-variant font-label-md tracking-wider uppercase\" data-el-bind=\"{{headerBinding1}}\">Settings</span></div></div><div class=\"flex items-center gap-space-sm\"><a class=\"w-11 h-11 flex items-center justify-center\" data-path=\"settings\" href=\"#\" data-el-action=\"{{headerAction1}}\"><img alt=\"Profile\" class=\"w-8 h-8 rounded-full object-cover ring-2 ring-primary/20\" src=\"../shared/images/image-3.jpg\"></a></div></div></div></header>"
  }
};
  const tabThemes = {
  "dashboard": {
    "navClass": "fixed bottom-0 w-full z-50 pb-safe bg-white/95 backdrop-blur-md border-t border-slate-200/80 shadow-[0_-2px_12px_rgba(17,27,47,0.06)]",
    "activeClasses": null,
    "tabClass": "flex flex-col items-center justify-center w-14 h-12 gap-0.5 text-slate-500 font-semibold text-xs hover:text-slate-900 transition-colors",
    "activeTabClass": "flex flex-col items-center justify-center w-14 h-12 gap-0.5 transition-colors text-sky-600 font-bold",
    "iconClass": "material-symbols-outlined text-[22px]",
    "activeIconClass": "material-symbols-outlined text-[22px] font-bold",
    "labelClass": "text-xs leading-none tracking-tight",
    "activeLabelClass": "text-xs font-bold leading-none tracking-tight",
    "activeIconStyle": null
  },
  "devices": {
    "navClass": "fixed bottom-0 w-full z-50 pb-safe bg-surface/90 backdrop-blur-xl border-t border-surface-container-high/60 shadow-lg",
    "activeClasses": "text-primary font-semibold",
    "tabClass": "flex flex-col items-center justify-center w-14 h-12 gap-0.5 text-on-surface-variant hover:text-on-surface transition-colors",
    "activeTabClass": "flex flex-col items-center justify-center w-14 h-12 gap-0.5 transition-colors text-primary font-bold",
    "iconClass": "material-symbols-outlined text-[22px]",
    "activeIconClass": "material-symbols-outlined text-[22px]",
    "labelClass": "font-label-md text-[12px] font-semibold leading-none tracking-tight",
    "activeLabelClass": "font-label-md text-[12px] font-bold leading-none tracking-tight",
    "activeIconStyle": null
  },
  "efficiency": {
    "navClass": "fixed bottom-0 w-full z-50 pb-safe bg-surface/90 backdrop-blur-xl border-t border-surface-variant/40 shadow-md",
    "activeClasses": "text-primary font-semibold",
    "tabClass": "flex flex-col items-center justify-center w-14 h-12 gap-0.5 text-on-surface-variant hover:text-on-surface transition-colors font-semibold",
    "activeTabClass": "flex flex-col items-center justify-center w-14 h-12 gap-0.5 transition-colors text-primary font-semibold",
    "iconClass": "material-symbols-outlined text-[22px]",
    "activeIconClass": "material-symbols-outlined text-[22px]",
    "labelClass": "font-label-md text-[11px] leading-none tracking-tight",
    "activeLabelClass": "font-label-md text-[11px] leading-none tracking-tight font-semibold",
    "activeIconStyle": "font-variation-settings: 'FILL' 1;"
  },
  "tips": {
    "navClass": "fixed bottom-0 w-full z-50 pb-safe bg-white/95 backdrop-blur border-t border-slate-200/80 shadow-[0_-2px_12px_rgba(0,0,0,0.04)]",
    "activeClasses": null,
    "tabClass": "flex flex-col items-center justify-center w-14 h-12 gap-0.5 text-slate-500 hover:text-slate-800 transition-colors font-semibold text-xs",
    "activeTabClass": "flex flex-col items-center justify-center w-14 h-12 gap-0.5 transition-colors text-sky-600 font-bold text-xs",
    "iconClass": "material-symbols-outlined text-[22px]",
    "activeIconClass": "material-symbols-outlined text-[22px] font-bold",
    "labelClass": "leading-none tracking-tight",
    "activeLabelClass": "leading-none tracking-tight",
    "activeIconStyle": null
  },
  "settings": {
    "navClass": "fixed bottom-0 w-full z-50 pb-safe bg-white/95 backdrop-blur border-t border-slate-200/80 shadow-[0_-2px_12px_rgba(0,0,0,0.04)]",
    "activeClasses": "text-primary font-semibold",
    "tabClass": "flex flex-col items-center justify-center w-14 h-12 gap-0.5 font-semibold text-xs text-slate-500 hover:text-slate-800 transition-colors",
    "activeTabClass": "flex flex-col items-center justify-center w-14 h-12 gap-0.5 transition-colors font-bold text-xs text-sky-600",
    "iconClass": "material-symbols-outlined text-[22px]",
    "activeIconClass": "material-symbols-outlined text-[22px] font-bold",
    "labelClass": "leading-none tracking-tight",
    "activeLabelClass": "leading-none tracking-tight",
    "activeIconStyle": "font-variation-settings: 'FILL' 1;"
  }
};
  const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[character]);
  const substitute = (template, values) => template.replace(/\{\{([^}]+)\}\}/g, (_, key) => {
    if (!(key in values)) throw new Error(`Missing chrome placeholder: ${key}`);
    return escapeHtml(values[key]);
  });
  const valuesFor = (config, prefix, actions, bindings) => {
    const values = {};
    actions.forEach((value, index) => { values[`${prefix}Action${index}`] = value; });
    bindings.forEach((value, index) => { values[`${prefix}Binding${index}`] = value; });
    return values;
  };
  // The five approved tab treatments are tokens; every page uses this one panel.
  const destinations = ['dashboard', 'devices', 'efficiency', 'perks-and-tips', 'settings'];
  const renderFooter = (config) => {
    const theme = tabThemes[config.activeTab];
    const selected = { dashboard: 'dashboard', devices: 'devices', efficiency: 'efficiency',
      tips: 'perks-and-tips', settings: 'settings' }[config.activeTab];
    const activeClasses = theme.activeClasses
      ? ` data-active-classes="${escapeHtml(theme.activeClasses)}"` : '';
    const tabs = destinations.map((destination, index) => {
      const active = destination === selected;
      const current = active ? ' aria-current="page"' : '';
      const tabClass = active ? theme.activeTabClass : theme.tabClass;
      const iconClass = active ? theme.activeIconClass : theme.iconClass;
      const labelClass = active ? theme.activeLabelClass : theme.labelClass;
      const iconStyle = active && theme.activeIconStyle
        ? ` style="${theme.activeIconStyle}"` : '';
      return `<a${current} class="${escapeHtml(tabClass)}" data-path="${destination}" href="#" data-el-action="${escapeHtml(config.footerActions[index])}"><span class="${escapeHtml(iconClass)}"${iconStyle}>${escapeHtml(config.tabIcons[index])}</span><span class="${escapeHtml(labelClass)}" data-el-bind="${escapeHtml(config.footerBindings[index])}">${escapeHtml(config.tabLabels[index])}</span></a>`;
    }).join('');
    return `<nav class="${escapeHtml(theme.navClass)}"${activeClasses}><div class="flex justify-around items-center h-16 px-space-xs">${tabs}</div></nav>`;
  };
  const mount = (config) => {
    const variant = variants[config.activeTab];
    if (!variant || config.headerBindings.length !== 2 || config.footerBindings.length !== 5 ||
        config.footerActions.length !== 5) throw new Error('Invalid design chrome configuration');
    const headerValues = valuesFor(config, 'header', config.headerActions, config.headerBindings);
    const headerHost = document.getElementById('el-header');
    const footerHost = document.getElementById('el-footer');
    headerHost.outerHTML = substitute(variant.header, headerValues);
    footerHost.outerHTML = renderFooter(config);
    const header = document.querySelector('body > header');
    const headerText = header.querySelectorAll('[data-el-bind]');
    headerText[0].textContent = config.homeName;
    headerText[1].textContent = config.pageLabel;
    header.querySelector('.material-symbols-outlined').textContent = config.leadingIcon;
    header.querySelector('img').src = config.profileImage;
    if (config.homeRoute) header.querySelector('button').dataset.elRoute = config.homeRoute;
  };
  window.EnergyLensChrome = Object.freeze({ mount });
})();
