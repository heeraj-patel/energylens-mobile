import 'package:flutter/material.dart';

import 'core/cloud_auth/cloud_entry_gate.dart';
import 'features/discovery/discovery_screen.dart';
import 'features/discovery/discovery_api.dart';
import 'features/discovery/discovery_credentials.dart';
import 'features/design/demo_report_preview_screen.dart';
import 'features/energy/cloud_report_preview_screen.dart';
import 'features/design/design_shell.dart';
import 'features/design/local_pilot_device_lifecycle.dart';

void main() => runApp(const EnergyLensApp());

const _green = Color(0xFF008F68);
const _ink = Color(0xFF0F172A);
const _line = Color(0xFFE1E8EE);

class EnergyLensApp extends StatelessWidget {
  const EnergyLensApp({
    super.key,
    this.localPilot = const bool.fromEnvironment('ENERGYLENS_LOCAL_PILOT'),
    this.localDiscoveryApi = const DiscoveryApi(),
    this.localDiscoveryCredentials = const DiscoveryCredentials(),
  });

  final bool localPilot;
  final DiscoveryApi localDiscoveryApi;
  final DiscoveryCredentials localDiscoveryCredentials;
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) {
      final dark = brightness == Brightness.dark;
      final scheme = ColorScheme.fromSeed(
        seedColor: _green,
        brightness: brightness,
      );
      return ThemeData(
        useMaterial3: true,
        fontFamily: 'Source Sans 3',
        colorScheme: scheme,
        scaffoldBackgroundColor: dark
            ? const Color(0xFF101B2D)
            : const Color(0xFFF8FAFC),
        appBarTheme: AppBarTheme(
          titleTextStyle: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: dark ? Colors.white : _ink,
          ),
          backgroundColor: dark ? const Color(0xFF172337) : Colors.white,
          foregroundColor: dark ? Colors.white : _ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: dark ? const Color(0xFF1D2A3D) : Colors.white,
          elevation: 1,
          shadowColor: const Color(0x141C4761),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: dark ? const Color(0xFF354558) : _line),
            borderRadius: BorderRadius.circular(22),
          ),
          margin: EdgeInsets.zero,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: dark ? const Color(0xFF172337) : Colors.white,
          indicatorColor: dark
              ? const Color(0xFF174A42)
              : const Color(0xFFE3F5ED),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(
              fontWeight: FontWeight.w600,
              color: dark ? Colors.white : _ink,
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'EnergyLens',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: localPilot
          ? DesignShell(
              localPilot: true,
              onReportPreview: () => _navigatorKey.currentState?.push(
                MaterialPageRoute<void>(
                  builder: (_) => const DemoReportPreviewScreen(),
                ),
              ),
              localDeviceLifecycle: LocalPilotDeviceLifecycle(
                api: localDiscoveryApi,
                credentials: localDiscoveryCredentials,
              ),
              designTour: const bool.fromEnvironment('ENERGYLENS_DESIGN_TOUR'),
              onDiscoverDevices: () async {
                await _navigatorKey.currentState?.push(
                  MaterialPageRoute<void>(
                    builder: (_) => DiscoveryScreen(
                      autoScan: true,
                      returnToSettingsAfterPairing: true,
                      api: localDiscoveryApi,
                      credentials: localDiscoveryCredentials,
                    ),
                  ),
                );
              },
            )
          : CloudEntryGate(
              newHomeBuilder:
                  (cloudHome, cloudApi, lifecycle, onCloudHubLinked) =>
                      DiscoveryScreen(
                        autoScan: true,
                        newHomeOnboarding: true,
                        cloudHome: cloudHome,
                        cloudApi: cloudApi,
                        accountId: lifecycle.verifiedAccountId,
                        onboardingDrafts: lifecycle.drafts,
                        onCloudHubLinked: onCloudHubLinked,
                      ),
              homeBuilder: (cloudHome, signOut, changeHome, cloudApi) =>
                  DesignShell(
                    homeName: cloudHome?.name ?? 'The Miller Home',
                    settingsApi: cloudApi,
                    onSignOut: signOut,
                    onChangeHome: changeHome,
                    onReportPreview: cloudHome == null
                        ? null
                        : () => _navigatorKey.currentState?.push(
                            MaterialPageRoute<void>(
                              builder: (_) => CloudReportPreviewScreen(
                                api: cloudApi,
                                home: cloudHome,
                              ),
                            ),
                          ),
                  ),
              verifiedDesignHomeBuilder:
                  (
                    cloudHome,
                    signOut,
                    changeHome,
                    cloudApi,
                    lifecycle,
                    designContextCoordinator,
                  ) => DesignShell(
                    homeName: cloudHome.name,
                    settingsApi: cloudApi,
                    onSignOut: signOut,
                    onChangeHome: changeHome,
                    designContextCoordinator: designContextCoordinator,
                    onboardingLifecycle: lifecycle,
                    onDiscoverDevices: () async {
                      final accountId = lifecycle.verifiedAccountId;
                      if (accountId == null ||
                          !lifecycle.isVerifiedScope(accountId, cloudHome.id)) {
                        return;
                      }
                      await _navigatorKey.currentState?.push(
                        MaterialPageRoute<void>(
                          builder: (_) => DiscoveryScreen(
                            autoScan: true,
                            returnToSettingsAfterPairing: true,
                            cloudHome: cloudHome,
                            cloudApi: cloudApi,
                            accountId: accountId,
                            onboardingDrafts: lifecycle.drafts,
                          ),
                        ),
                      );
                    },
                    onReportPreview: () {
                      final accountId = lifecycle.verifiedAccountId;
                      if (accountId == null ||
                          !lifecycle.isVerifiedScope(accountId, cloudHome.id)) {
                        return;
                      }
                      _navigatorKey.currentState?.push(
                        MaterialPageRoute<void>(
                          builder: (_) => CloudReportPreviewScreen(
                            api: cloudApi,
                            home: cloudHome,
                            lifecycle: lifecycle,
                            accountId: accountId,
                          ),
                        ),
                      );
                    },
                  ),
            ),
    );
  }
}
