(() => {
  const answerSelector = '[data-faq-answer]';
  const triggerSelector = '[data-faq-trigger][aria-controls]';

  function getPanel(trigger) {
    return document.getElementById(trigger.getAttribute('aria-controls'));
  }

  function ensureExpandControl(answer) {
    let control = answer.nextElementSibling?.querySelector('.faq-answer-expand');
    if (control) return control;

    const row = document.createElement('div');
    row.className = 'flex justify-end mt-1';
    control = document.createElement('button');
    control.className = 'faq-answer-expand inline-flex items-center justify-center w-8 h-8 rounded-full text-on-surface-variant hover:bg-slate-100 focus:outline-none focus:ring-2 focus:ring-primary/50';
    control.type = 'button';
    control.hidden = true;
    control.setAttribute('aria-label', 'Show full answer');
    control.setAttribute('aria-expanded', 'false');
    control.innerHTML = '<span class="material-symbols-outlined text-[20px]" aria-hidden="true">expand_more</span>';
    row.append(control);
    answer.after(row);
    return control;
  }

  function measure(answer) {
    const control = ensureExpandControl(answer);
    const wasExpanded = control.getAttribute('aria-expanded') === 'true';
    answer.classList.add('faq-answer-collapsed');
    const hasMore = answer.scrollHeight > answer.clientHeight + 1;
    control.hidden = !hasMore;
    if (!hasMore) {
      answer.classList.remove('faq-answer-collapsed');
      control.setAttribute('aria-expanded', 'false');
      control.setAttribute('aria-label', 'Show full answer');
      control.querySelector('span').textContent = 'expand_more';
    } else if (wasExpanded) {
      answer.classList.remove('faq-answer-collapsed');
    }
  }

  function setOpen(trigger, open) {
    const panel = getPanel(trigger);
    if (!panel) return;
    panel.classList.toggle('hidden', !open);
    trigger.setAttribute('aria-expanded', String(open));
    const icon = trigger.querySelector('[data-faq-trigger-icon]');
    if (icon) icon.textContent = open ? 'remove' : 'add';

    const answer = panel.querySelector(answerSelector);
    if (!answer) return;
    const control = ensureExpandControl(answer);
    if (open) {
      requestAnimationFrame(() => measure(answer));
    } else {
      answer.classList.add('faq-answer-collapsed');
      control.hidden = true;
      control.setAttribute('aria-expanded', 'false');
      control.setAttribute('aria-label', 'Show full answer');
      control.querySelector('span').textContent = 'expand_more';
    }
  }

  document.addEventListener('click', (event) => {
    const expand = event.target.closest('.faq-answer-expand');
    if (expand) {
      const answer = expand.parentElement.previousElementSibling;
      if (!answer?.matches(answerSelector)) return;
      const expanded = expand.getAttribute('aria-expanded') === 'true';
      answer.classList.toggle('faq-answer-collapsed', expanded);
      expand.setAttribute('aria-expanded', String(!expanded));
      expand.setAttribute('aria-label', expanded ? 'Show full answer' : 'Show less');
      expand.querySelector('span').textContent = expanded ? 'expand_more' : 'expand_less';
      return;
    }

    const trigger = event.target.closest(triggerSelector);
    if (trigger) setOpen(trigger, trigger.getAttribute('aria-expanded') !== 'true');
  });

  const answers = [...document.querySelectorAll(answerSelector)];
  for (const answer of answers) {
    ensureExpandControl(answer);
    if (typeof MutationObserver !== 'undefined') {
      new MutationObserver(() => requestAnimationFrame(() => {
        const panel = answer.closest('[id]');
        if (panel && !panel.classList.contains('hidden')) measure(answer);
      })).observe(answer, { childList: true, characterData: true, subtree: true });
    }
  }

  window.addEventListener('resize', () => {
    for (const answer of answers) {
      const panel = answer.closest('[id]');
      if (panel && !panel.classList.contains('hidden')) measure(answer);
    }
  });
})();
