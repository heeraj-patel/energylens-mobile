import 'package:energylens_mobile/features/energy/local_pilot_programs.dart';
import 'package:energylens_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _Launcher extends UrlLauncherPlatform {
  String? openedUrl;
  PreferredLaunchMode? mode;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    openedUrl = url;
    mode = options.mode;
    return true;
  }
}

void main() {
  testWidgets('local pilot DOE offer opens its official source externally', (
    tester,
  ) async {
    final previousLauncher = UrlLauncherPlatform.instance;
    final launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalPilotPrograms(now: DateTime.utc(2026, 10, 5)),
        ),
      ),
    );
    expect(find.text('Federal'), findsOneWidget);
    expect(find.text('Weatherization Assistance Program'), findsOneWidget);
    expect(find.text('Weatherization services'), findsOneWidget);
    expect(find.text('U.S. Department of Energy'), findsOneWidget);
    expect(find.text(localPilotWapSourceUrl.toString()), findsOneWidget);
    expect(
      localPilotWapSourceSha256,
      '05d32356150408fec895bc2751a369e20273abafa471e3e1fd959cab9bf4fc74',
    );
    await tester.tap(find.byKey(const Key('localPilotWapProgram')));
    await tester.pump();
    expect(launcher.openedUrl, localPilotWapSourceUrl.toString());
    expect(launcher.mode, PreferredLaunchMode.externalApplication);
  });

  testWidgets('local pilot offer disappears at review expiry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalPilotPrograms(
            now: DateTime.parse(localPilotWapReviewExpiresAt),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('localPilotWapProgram')), findsNothing);
  });

  testWidgets('nonpilot local home keeps heading without DOE fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(initialTabIndex: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Programs'), findsOneWidget);
    expect(find.byKey(const Key('localPilotWapProgram')), findsNothing);
  });
}
