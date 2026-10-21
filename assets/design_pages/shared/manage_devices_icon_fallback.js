/* Local outlines from the bundled Material Symbols font for Manage Devices only. */
(() => {
  const data = window.EnergyLensManageDevicesIconPaths;
  if (!data) return;
  const namespace = 'http://www.w3.org/2000/svg';
  const tokenClass = 'el-md-icon-token';
  const svgClass = 'el-md-icon-svg';
  const iconSelector = '.material-symbols-outlined';
  const fillSetting = /["']FILL["']\s+([01])\b/;
  const weightSetting = /["']wght["']\s+(\d+(?:\.\d+)?)\b/;

  function ownChild(host, className) {
    return Array.from(host.children).find((child) => child.classList.contains(className));
  }

  function render(host) {
    const existingToken = ownChild(host, tokenClass);
    const token = (existingToken || host).textContent.trim();
    const variants = data.paths;
    const outline = variants['400']['0'][token];
    const previousSvg = ownChild(host, svgClass);
    if (!outline) {
      if (existingToken && previousSvg) host.textContent = token;
      return;
    }
    const computed = getComputedStyle(host);
    const settings = computed.fontVariationSettings || '';
    const fill = fillSetting.exec(settings)?.[1] || '0';
    const numericWeight = Number(weightSetting.exec(settings)?.[1] || computed.fontWeight);
    const weight = numericWeight >= 550 ? '700' : '400';
    const path = variants[weight][fill][token] || outline;
    if (previousSvg && previousSvg.getAttribute('data-token') === token &&
        previousSvg.getAttribute('data-fill') === fill &&
        previousSvg.getAttribute('data-weight') === weight) return;

    const svg = document.createElementNS(namespace, 'svg');
    svg.classList.add(svgClass);
    svg.setAttribute('viewBox', data.viewBox);
    svg.setAttribute('width', '1em');
    svg.setAttribute('height', '1em');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');
    svg.setAttribute('data-token', token);
    svg.setAttribute('data-fill', fill);
    svg.setAttribute('data-weight', weight);
    svg.style.cssText = 'display:block;fill:currentColor;flex:none';
    const shape = document.createElementNS(namespace, 'path');
    shape.setAttribute('d', path);
    svg.appendChild(shape);

    if (existingToken) {
      if (previousSvg) previousSvg.replaceWith(svg);
      else host.appendChild(svg);
    } else {
      const hiddenToken = document.createElement('span');
      hiddenToken.className = tokenClass;
      hiddenToken.textContent = token;
      host.replaceChildren(hiddenToken, svg);
    }
  }

  function scan() {
    document.querySelectorAll(iconSelector).forEach(render);
  }

  function start() {
    scan();
    let queued = false;
    new MutationObserver(() => {
      if (queued) return;
      queued = true;
      queueMicrotask(() => {
        queued = false;
        scan();
      });
    }).observe(document.body, {
      childList: true, characterData: true, attributes: true,
      attributeFilter: ['class', 'style', 'aria-current'], subtree: true,
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, {once: true});
  } else {
    start();
  }
})();
