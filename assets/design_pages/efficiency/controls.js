(() => {
  const toggle = document.getElementById('efficiency-details-toggle');
  const details = document.getElementById('efficiency-details');
  if (!toggle || !details) return;

  toggle.addEventListener('click', () => {
    const expanded = toggle.getAttribute('aria-expanded') !== 'true';
    toggle.setAttribute('aria-expanded', String(expanded));
    toggle.textContent = expanded ? 'Hide details' : 'View details';
    details.hidden = !expanded;
    details.classList.toggle('hidden', !expanded);
  });
})();
