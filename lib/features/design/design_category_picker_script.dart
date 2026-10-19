import 'dart:convert';

import '../../core/cloud_api/cloud_energy_categories.dart';

/// Populate the existing key controls and the approved exposed dropdowns.
String buildDesignCategoryPickerScript(EnergyCategories categories) {
  final groups = jsonEncode(
    categories.groups
        .map(
          (group) => {
            'key': group.key,
            'label': group.label,
            'types': group.types
                .map((type) => {'key': type.key, 'label': type.label})
                .toList(),
          },
        )
        .toList(),
  );
  return '''
    (() => {
      const groups = $groups;
      const category = document.getElementById('energy-category');
      const type = document.getElementById('energy-type');
      if (!category || !type) return false;
      const option = (value, label) => new Option(label, value);
      const oldGroup = category.value, oldType = type.value;
      const selectGroup = () => {
        const group = groups.find((item) => item.key === category.value);
        type.replaceChildren(option('', group ? 'Choose type' : 'Choose category first'));
        for (const item of group?.types || []) type.add(option(item.key, item.label));
        type.disabled = !group;
      };
      category.replaceChildren(option('', 'Choose category'));
      for (const group of groups) category.add(option(group.key, group.label));
      category.value = groups.some((group) => group.key === oldGroup) ? oldGroup : '';
      category.disabled = groups.length === 0;
      category.addEventListener('change', selectGroup);
      selectGroup();
      if (Array.from(type.options).some((item) => item.value === oldType)) type.value = oldType;

      const fields = {
        category: document.getElementById('dd-category'),
        type: document.getElementById('dd-type'),
      };
      const menus = {
        category: document.getElementById('menu-category'),
        type: document.getElementById('menu-type'),
      };
      const values = {
        category: document.getElementById('dd-category-value'),
        type: document.getElementById('dd-type-value'),
      };
      // Existing script fixtures and any old page still use the selects alone.
      if (!fields.category || !fields.type || !menus.category || !menus.type) {
        window.energyLensSelectType = (key) => {
          const group = groups.find((item) => item.types.some((entry) => entry.key === key));
          if (!group) return;
          category.value = group.key;
          selectGroup();
          type.value = key;
        };
        return true;
      }
      const icons = {
        heating_cooling: 'thermostat', refrigeration: 'kitchen', cooking: 'skillet',
        dishwashing_laundry: 'local_laundry_service', water_heating: 'water_heater',
        tv_entertainment: 'tv', work_technology: 'computer',
        network_smart_home: 'router', lighting: 'lightbulb', other: 'more_horiz',
      };
      const group = () => groups.find((item) => item.key === category.value);
      const rows = (which) => Array.from(menus[which].querySelectorAll('[role="option"]'));
      const isOpen = (which) => fields[which].getAttribute('aria-expanded') === 'true';
      const paint = () => {
        const selectedGroup = group();
        values.category.textContent = selectedGroup?.label || 'Choose category';
        document.getElementById('dd-category-icon').textContent =
          icons[selectedGroup?.key] || 'category';
        fields.category.classList.toggle('has-value', !!selectedGroup);
        fields.category.setAttribute('aria-disabled', String(groups.length === 0));
        const selectedType = selectedGroup?.types.find((item) => item.key === type.value);
        values.type.textContent = selectedType?.label ||
          (selectedGroup ? 'Choose type' : 'Choose category first');
        fields.type.classList.toggle('has-value', !!selectedType);
        fields.type.setAttribute('aria-disabled', String(!selectedGroup));
      };
      const close = (which, restoreFocus) => {
        const wasOpen = isOpen(which);
        menus[which].classList.add('hidden');
        fields[which].setAttribute('aria-expanded', 'false');
        fields[which].removeAttribute('aria-activedescendant');
        if (wasOpen && restoreFocus) fields[which].focus();
        return wasOpen;
      };
      const dismiss = () => {
        const categoryOpen = close('category', false);
        const typeOpen = close('type', false);
        if (categoryOpen) fields.category.focus();
        if (typeOpen) fields.type.focus();
        return categoryOpen || typeOpen;
      };
      const active = (which, index) => {
        const items = rows(which);
        items.forEach((item, i) => item.classList.toggle('is-active', i === index));
        if (items[index]) {
          fields[which].setAttribute('aria-activedescendant', items[index].id);
          items[index].scrollIntoView({block: 'nearest'});
        }
      };
      const render = (which) => {
        const items = which === 'category' ? groups : (group()?.types || []);
        menus[which].replaceChildren();
        items.forEach((item, index) => {
          const row = document.createElement('li');
          row.id = which + '-opt-' + index;
          row.className = 'el-menu-item text-sm font-body-md';
          row.dataset.value = item.key;
          row.setAttribute('role', 'option');
          row.setAttribute('aria-selected', String(item.key ===
            (which === 'category' ? category.value : type.value)));
          if (which === 'category') {
            const icon = document.createElement('span');
            icon.className = 'el-menu-icon material-symbols-outlined text-[20px]';
            icon.setAttribute('aria-hidden', 'true');
            icon.textContent = icons[item.key] || 'category';
            row.append(icon);
          }
          const label = document.createElement('span');
          label.textContent = item.label;
          row.append(label);
          const check = document.createElement('span');
          check.className = 'el-menu-check material-symbols-outlined text-[20px]';
          check.setAttribute('aria-hidden', 'true');
          check.textContent = 'check';
          row.append(check);
          menus[which].append(row);
        });
      };
      const place = (which) => {
        const menu = menus[which];
        menu.classList.remove('opens-up');
        menu.style.maxHeight = '';
        const rect = fields[which].getBoundingClientRect();
        const navRect = document.querySelector('.el-app-nav')?.getBoundingClientRect();
        const bottom = navRect && navRect.width > navRect.height
          ? navRect.top : window.innerHeight;
        const below = bottom - rect.bottom - 12, above = rect.top - 80;
        const wanted = Math.min(menu.scrollHeight,
          parseFloat(getComputedStyle(menu).maxHeight) || 368);
        if (below < Math.min(wanted, 240) && above > below) {
          menu.classList.add('opens-up');
          menu.style.maxHeight = String(Math.max(48, Math.min(wanted, above))) + 'px';
        } else {
          menu.style.maxHeight = String(Math.max(48, Math.min(wanted, below))) + 'px';
        }
      };
      const open = (which) => {
        if (fields[which].getAttribute('aria-disabled') === 'true') return;
        close(which === 'category' ? 'type' : 'category', false);
        render(which);
        menus[which].classList.remove('hidden');
        fields[which].setAttribute('aria-expanded', 'true');
        place(which);
        const selected = rows(which).findIndex((item) =>
          item.getAttribute('aria-selected') === 'true');
        active(which, selected < 0 ? 0 : selected);
      };
      const choose = (which, key) => {
        if (which === 'category') {
          if (category.value !== key) {
            category.value = key;
            selectGroup();
            type.value = '';
          }
          paint();
          close(which, false);
          fields.type.focus();
        } else {
          type.value = key;
          paint();
          close(which, true);
        }
      };
      for (const which of ['category', 'type']) {
        fields[which].addEventListener('click', () =>
          isOpen(which) ? close(which, true) : open(which));
        fields[which].addEventListener('keydown', (event) => {
          if (!isOpen(which)) {
            if (['ArrowDown', 'ArrowUp', 'Enter', ' '].includes(event.key)) {
              event.preventDefault();
              open(which);
            }
            return;
          }
          const items = rows(which);
          const index = items.findIndex((item) => item.classList.contains('is-active'));
          if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
            event.preventDefault();
            active(which, event.key === 'Home' ? 0 : event.key === 'End' ? items.length - 1
              : event.key === 'ArrowDown' ? Math.min(index + 1, items.length - 1)
              : Math.max(index - 1, 0));
          } else if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            if (items[index]) choose(which, items[index].dataset.value);
          } else if (event.key === 'Escape' || event.key === 'Tab') {
            close(which, event.key === 'Escape');
          }
        });
        menus[which].addEventListener('click', (event) => {
          const row = event.target.closest('[role="option"]');
          if (row) choose(which, row.dataset.value);
        });
      }
      document.addEventListener('click', (event) => {
        for (const which of ['category', 'type']) {
          if (!event.target.closest('[data-dd="' + which + '"]')) close(which, false);
        }
      });
      window.energyLensSelectType = (key) => {
        const selectedGroup = groups.find((item) =>
          item.types.some((entry) => entry.key === key));
        if (!selectedGroup) return;
        category.value = selectedGroup.key;
        selectGroup();
        type.value = key;
        paint();
      };
      window.EnergyLensDevicePicker = Object.freeze({
        dismiss,
        set(groupKey, typeKey, roomName) {
          category.value = groups.some((item) => item.key === groupKey) ? groupKey : '';
          selectGroup();
          type.value = Array.from(type.options).some((item) => item.value === typeKey)
            ? typeKey : '';
          if (roomName !== undefined) {
            const room = document.getElementById('input-room');
            if (room) {
              room.value = roomName || '';
              room.dispatchEvent(new Event('input', {bubbles: true}));
            }
          }
          paint();
        },
      });
      paint();
      return true;
    })()
  ''';
}
