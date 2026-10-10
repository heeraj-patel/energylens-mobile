import 'dart:convert';

/// Installs local navigation on one approved design page.
String buildDesignNavigationScript(String page) {
  final currentPage = jsonEncode(page);
  return '''
    (() => {
      const page = $currentPage;
      const send = (route) => EnergyLensNavigation.postMessage(route);
      const textOf = (element) => {
        const clone = element.cloneNode(true);
        clone.querySelectorAll('.material-symbols-outlined').forEach((node) => node.remove());
        return clone.textContent.replace(/\\s+/g, ' ').trim();
      };
      document.addEventListener('click', (event) => {
        const link = event.target.closest('a[data-path]');
        if (link) {
          const label = textOf(link);
          const route = page === 'devices' && link.dataset.elAction === 'devices_action_003'
            ? 'dashboard'
            : label.includes('Manage Devices')
              ? 'settings_manage_devices'
              : ({'perks-and-tips': 'perks_tips'}[link.dataset.path] || link.dataset.path);
          event.preventDefault();
          event.stopImmediatePropagation();
          send(route);
          return;
        }
        const button = event.target.closest('button');
        if (!button) return;
        const action = button.dataset.elAction;
        if (page === 'settings' && (action === 'settings_action_edit_home' || action === 'settings_action_edit_zip')) {
          event.preventDefault();
          event.stopImmediatePropagation();
          send('edit_home_details');
          return;
        }
        if (page === 'settings' && {
          settings_action_edit_owner: 'edit_account_owner',
          settings_action_edit_email: 'edit_account_email',
          settings_action_change_password: 'change_account_password'
        }[action]) {
          event.preventDefault();
          event.stopImmediatePropagation();
          send({
            settings_action_edit_owner: 'edit_account_owner',
            settings_action_edit_email: 'edit_account_email',
            settings_action_change_password: 'change_account_password'
          }[action]);
          return;
        }
        if (page === 'settings' && action === 'settings_action_011') {
          event.preventDefault();
          event.stopImmediatePropagation();
          send('report_preview');
          return;
        }
        if (page === 'settings_manage_devices' &&
            action === 'settings_manage_devices_action_005') {
          event.preventDefault();
          event.stopImmediatePropagation();
          send('discover_devices');
          return;
        }
        const savedApplianceId = button.getAttribute?.('data-el-delete-appliance-id');
        if (savedApplianceId) {
          event.preventDefault();
          event.stopImmediatePropagation();
          EnergyLensDeleteDevice.postMessage(savedApplianceId);
          return;
        }
        if (page === 'settings_manual_device_entry' &&
            button.matches?.('button.type-pill[data-el-action]') == true) {
          event.preventDefault();
          event.stopImmediatePropagation();
          for (const pill of document.querySelectorAll('button.type-pill[data-el-action]')) {
            const selected = pill === button;
            pill.classList.toggle('bg-primary-container', selected);
            pill.classList.toggle('text-on-primary-container', selected);
            pill.classList.toggle('font-semibold', selected);
            pill.classList.toggle('bg-surface-container-low', !selected);
            pill.classList.toggle('text-on-surface-variant', !selected);
            pill.setAttribute('aria-pressed', String(selected));
          }
          return;
        }
        if (page === 'dashboard' &&
            ['dashboard_action_004', 'dashboard_action_005', 'dashboard_action_006'].includes(action)) {
          event.preventDefault();
          event.stopImmediatePropagation();
          send('dashboard_period:' + ({
            dashboard_action_004: 'day',
            dashboard_action_005: 'week',
            dashboard_action_006: 'month'
          })[action]);
          return;
        }
        if (page === 'dashboard' && action === 'dashboard_action_007') {
          event.preventDefault();
          event.stopImmediatePropagation();
          send('tips_knowledge');
          return;
        }
        if ((page === 'settings_manage_devices' || page === 'settings_manual_device_entry') &&
            action === page + '_action_020') {
          event.preventDefault();
          event.stopImmediatePropagation();
          const selectedType = Array.from(document.querySelectorAll('button.type-pill[data-el-action]'))
            .find((element) => element.dataset.elAction?.startsWith(page + '_action_01') &&
              (element.classList.contains('bg-primary-container') || element.getAttribute('aria-pressed') === 'true'));
          const categoryByAction = page === 'settings_manual_device_entry' ? {
            [page + '_action_014']: 'air_conditioner',
            [page + '_action_015']: 'refrigerator',
            [page + '_action_016']: 'television',
            [page + '_action_017']: 'computer',
            [page + '_action_018']: 'dishwasher',
            [page + '_action_019']: 'water_heater'
          } : {
            [page + '_action_014']: 'air_conditioner',
            [page + '_action_015']: 'dishwasher',
            [page + '_action_016']: 'television',
            [page + '_action_017']: 'computer',
            [page + '_action_018']: 'lighting',
            [page + '_action_019']: 'other'
          };
          EnergyLensDeviceReview.postMessage(JSON.stringify({
            name: document.getElementById('input-device-name')?.value || '',
            manufacturer: document.getElementById('input-manufacturer')?.value || '',
            model: document.getElementById('input-model')?.value || '',
            category: categoryByAction[selectedType?.dataset.elAction] || ''
          }));
          return;
        }
        if (page === 'settings_photo_scan_onboarding' &&
            (action === page + '_action_014' || action === page + '_action_015')) {
          event.preventDefault();
          event.stopImmediatePropagation();
          EnergyLensPhotoCapture.postMessage(action.endsWith('014') ? 'camera' : 'gallery');
          return;
        }
        if (page === 'settings_photo_scan_onboarding' &&
            (action === page + '_action_013' || action === page + '_action_022')) {
          event.preventDefault();
          event.stopImmediatePropagation();
          return;
        }
        if (page === 'settings_manage_devices' && action === page + '_action_013') {
          event.preventDefault();
          event.stopImmediatePropagation();
          return;
        }
        const label = textOf(button);
        let route = button.dataset.elRoute;
        if (button.id === 'email-btn') route = 'report_preview';
        else if (route !== 'change_home' && page.startsWith('efficiency')) {
          if (label === 'Night') route = 'efficiency';
          else if (label === 'Away') route = 'efficiency_away';
          else if (label === 'Peak Rates') route = 'efficiency_peak_rates';
          else if (label === 'Habits') route = 'efficiency_habits';
        } else if ((page === 'perks_tips' || page.startsWith('tips_')) &&
                   button.closest('[role="tablist"]')) {
          if (label === 'Programs') route = 'perks_tips';
          else if (label === 'Efficiency') route = 'tips_efficiency';
          else if (label === 'Care & Upgrades') route = 'tips_care_upgrades';
          else if (label === 'Knowledge') route = 'tips_knowledge';
        } else if (page.startsWith('settings')) {
          if (label === 'Profile & Reports') route = 'settings';
          else if (label === 'Manage Devices') route = 'settings_manage_devices';
          else if (label.startsWith('Auto Scan')) route = 'settings_manage_devices';
          else if (label.startsWith('Photo Scan') || label.startsWith('Snap Photo')) route = 'settings_photo_scan_onboarding';
          else if (label.startsWith('Manual Form') || label.startsWith('Type In Manual')) route = 'settings_manual_device_entry';
          else if (label === 'Sign Out') route = 'sign_out';
        }
        if (route) {
          event.preventDefault();
          event.stopImmediatePropagation();
          send(route);
        }
      }, true);
    })();
  ''';
}
