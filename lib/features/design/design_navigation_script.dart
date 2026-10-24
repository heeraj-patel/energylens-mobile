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
        const deviceCard = page === 'devices'
          ? event.target.closest('[data-el-live-device-id]') : null;
        if (deviceCard && !event.target.closest('a, button, select, input')) {
          event.preventDefault();
          event.stopImmediatePropagation();
          send('device_detail:' + deviceCard.getAttribute('data-el-live-device-id') +
            ':' + (deviceCard.getAttribute('data-el-device-name') || ''));
          return;
        }
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
        const editApplianceId = button.getAttribute?.('data-el-edit-appliance-id');
        if (page === 'settings_manage_devices' && editApplianceId) {
          event.preventDefault();
          event.stopImmediatePropagation();
          send('edit_appliance:' + editApplianceId);
          return;
        }
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
          if (typeof window.selectOnboardingMethod === 'function') {
            window.selectOnboardingMethod('scan');
          }
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
        if (page === 'dashboard' &&
            ['dashboard_action_004', 'dashboard_action_005', 'dashboard_action_006'].includes(action)) {
          event.preventDefault();
          event.stopImmediatePropagation();
          const period = ({
            dashboard_action_004: 'day',
            dashboard_action_005: 'week',
            dashboard_action_006: 'month'
          })[action];
          window.__energyLensDashboardRequestedPeriod = period;
          send('dashboard_period:' + period);
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
          EnergyLensDeviceReview.postMessage(JSON.stringify({
            name: document.getElementById('input-device-name')?.value || '',
            manufacturer: document.getElementById('input-manufacturer')?.value || '',
            model: document.getElementById('input-model')?.value || '',
            group: document.getElementById('energy-category')?.value || '',
            category: document.getElementById('energy-type')?.value || '',
            room: document.getElementById('input-room')?.value || ''
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
        if (page === 'dashboard' && route === 'settings_manage_devices' &&
            label === 'Add device') route = 'discover_devices';
        if (button.id === 'email-btn') route = 'report_preview';
        else if (route !== 'change_home' && page.startsWith('efficiency')) {
          if (label === 'Night') route = 'efficiency';
          else if (label === 'Away') route = 'efficiency_away';
          else if (label === 'Peak Rates') route = 'efficiency_peak_rates';
          else if (label === 'Habits') route = 'efficiency_habits';
        } else if ((page === 'perks_tips' || page.startsWith('tips_')) &&
                   button.closest('[role="tablist"]')) {
          if (label === 'Programs') route = 'perks_tips';
          else if (label === 'General Tips') route = 'tips_efficiency';
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
