import 'dart:convert';

import 'knowledge_domain_repository.dart';
import 'knowledge_question_catalog.dart';

/// Installs all approved FAQ labels in the existing Knowledge card.
/// Answers without matching evidence use the owner-approved fallback.
String buildKnowledgePageScript({bool localPilot = false}) {
  final entries = KnowledgeDomainRepository.bundledCatalog.entries
      .map(
        (entry) => <String, Object>{
          'id': entry.id,
          'question': entry.question,
          'answer':
              entry.availability == KnowledgeCatalogAvailability.localPilot &&
                  !localPilot
              ? "We can't answer this right now."
              : entry.preparedAnswer ?? "We can't answer this right now.",
          'aliases': entry.aliases,
        },
      )
      .toList();
  final data = jsonEncode(entries);
  return '''
    (() => {
      const entries = $data;
      const input = document.querySelector('[data-el-field="tips_knowledge_field_001"]');
      const existing = document.getElementById('faq-1-content')?.parentElement?.parentElement;
      if (!input || !existing) return false;
      const template = document.getElementById('faq-1-content')?.parentElement;
      if (!template) return false;
      const cards = new Map();
      const pilotIds = ['ac_afternoon', 'standby_cost', 'laundry_now'];
      for (let i = 0; i < pilotIds.length; i++) {
        const card = document.getElementById('faq-' + (i + 1) + '-content')?.parentElement;
        if (card) {
          const entry = entries.find((item) => item.id === pilotIds[i]);
          if (entry) card.querySelector('[data-faq-answer]').textContent = entry.answer;
          cards.set(pilotIds[i], card);
        }
      }
      for (const entry of entries) {
        if (cards.has(entry.id)) continue;
        const card = template.cloneNode(true);
        const panel = card.querySelector('[id]');
        const trigger = card.querySelector('[data-faq-trigger]');
        const label = trigger?.querySelector('[data-el-bind]');
        const answer = card.querySelector('[data-faq-answer]');
        if (!panel || !trigger || !label || !answer) continue;
        panel.id = 'faq-' + entry.id + '-content';
        trigger.setAttribute('aria-controls', panel.id);
        trigger.setAttribute('aria-expanded', 'false');
        trigger.removeAttribute('data-el-action');
        trigger.querySelector('.material-symbols-outlined.text-primary')?.remove();
        label.removeAttribute('data-el-bind');
        label.classList.remove('truncate');
        label.textContent = entry.question;
        answer.removeAttribute('data-el-bind');
        answer.textContent = entry.answer;
        card.querySelectorAll('.faq-answer-expand').forEach((node) => node.parentElement?.remove());
        existing.append(card);
        cards.set(entry.id, card);
      }
      const normalize = (value) => value.toLocaleLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
      const stopWords = new Set(['the', 'and', 'for', 'what', 'where', 'when', 'why', 'how', 'my', 'does', 'are', 'can', 'could', 'with']);
      const near = (word, term) => {
        if (word === term) return true;
        if (Math.abs(word.length - term.length) > 1 || term.length < 4) return false;
        let i = 0, j = 0, edits = 0;
        while (i < word.length && j < term.length) {
          if (word[i] === term[j]) { i++; j++; continue; }
          if (++edits > 1) return false;
          if (word[i + 1] === term[j] && word[i] === term[j + 1]) { i += 2; j += 2; }
          else if (word.length > term.length) i++;
          else if (term.length > word.length) j++;
          else { i++; j++; }
        }
        return edits + (word.length - i) + (term.length - j) <= 1;
      };
      const visible = () => {
        const query = normalize(input.value);
        const terms = query.split(' ').filter((word) => word.length > 2 && !stopWords.has(word));
        for (const id of pilotIds) {
          const card = cards.get(id);
          if (card) card.hidden = !entries.some((entry) => entry.id === id);
        }
        for (const entry of entries) {
          const card = cards.get(entry.id);
          if (!card) continue;
          const label = normalize(entry.question);
          const aliases = entry.aliases.map(normalize);
          const words = normalize([entry.question, ...entry.aliases].join(' ')).split(' ');
          const matched = !query || label.includes(query) || aliases.some((alias) => alias.includes(query)) ||
            (terms.length > 0 && terms.every((term) => words.some((word) => near(word, term))));
          card.hidden = !matched;
          if (matched) {
            const exact = label.includes(query) ? 100 : 0;
            const related = aliases.some((alias) => alias.includes(query)) ? 45 : 0;
            const overlap = terms.filter((term) => words.some((word) => near(word, term))).length;
            card.style.order = String(-(exact + related + overlap * 10));
          }
        }
      };
      input.addEventListener('input', (event) => {
        event.stopImmediatePropagation();
        visible();
      }, true);
      visible();
      existing.classList.remove('hidden');
      return true;
    })();
  ''';
}
