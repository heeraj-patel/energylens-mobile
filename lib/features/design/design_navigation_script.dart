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
