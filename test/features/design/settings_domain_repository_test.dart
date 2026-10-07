import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_preferences.dart';
import 'package:energylens_mobile/features/design/settings_domain_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';

CloudHome cloudHome(String id, {String name = 'Home'}) => CloudHome(
  id: id,
  name: name,
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);

CloudAppliance appliance(String homeId, String id) => CloudAppliance(
  id: id,
  homeId: homeId,
  name: 'Appliance',
  category: 'other',
  room: null,
  brand: 'Brand',
  fullModel: 'Model',
  fuel: 'electric',
  matchQuality: 'user_entered',
);

CloudVersioned<CloudAccountPreferences> accountPrefs() => const CloudVersioned(
  value: CloudAccountPreferences(
    version: 1,
    emailReportsEnabled: true,
    historyDisclosureAcceptedAt: null,
  ),
  etag: '"1"',
);

CloudVersioned<CloudHomePreferences> homePrefs() => const CloudVersioned(
  value: CloudHomePreferences(
    version: 1,
    goal: 'unspecified',
    comfortPriority: 'unknown',
  ),
  etag: '"1"',
);

class FakeSource implements SettingsDomainSource {
  FakeSource({this.email, this.homeRead, this.homesResult, this.applianceRead});

  final String? email;
  final Future<CloudVersioned<CloudHome>> Function(String)? homeRead;
  final List<CloudHome>? homesResult;
  final List<CloudAppliance> Function(String)? applianceRead;

  @override
  Future<CloudAccount> account() async =>
      CloudAccount(id: 'account-id', email: email, emailVerified: false);
  @override
  Future<List<CloudHome>> homes() async =>
      homesResult ?? [cloudHome(homeA), cloudHome(homeB, name: 'Other home')];
  @override
  Future<CloudVersioned<CloudAccountPreferences>> accountPreferences() async =>
      accountPrefs();
  @override
  Future<CloudVersioned<CloudHome>> home(String homeId) =>
      homeRead?.call(homeId) ??
      Future.value(CloudVersioned(value: cloudHome(homeId), etag: '"4"'));
  @override
  Future<CloudVersioned<CloudHomePreferences>> homePreferences(
    String homeId,
  ) async => homePrefs();
  @override
  Future<List<CloudAppliance>> appliances(String homeId) async =>
      applianceRead?.call(homeId) ?? [appliance(homeId, 'appliance-1')];
}

void main() {
  test(
    'composes account, selected home, preferences and inventory safely',
    () async {
      final result = await SettingsDomainRepository(
        FakeSource(email: 'owner@example.com'),
      ).fetch(homeA);

      expect(result?.account.id, 'account-id');
      expect(result?.email, 'owner@example.com');
      expect(result?.emailVerified, isFalse);
      expect(result?.homes, hasLength(2));
      expect(result?.home.name, 'Home');
      expect(result?.postalCode, '60601');
      expect(result?.homeEtag, '"4"');
      expect(result?.emailReportsEnabled, isTrue);
      expect(result?.homePreferences.goal, 'unspecified');
      expect(result?.homePreferencesEtag, '"1"');
      expect(result?.applianceCount, 1);
      expect(result?.appliances.single.matchQuality, 'user_entered');
    },
  );

  test(
    'retains absent email and empty inventory as unknown or empty',
    () async {
      final result = await SettingsDomainRepository(
        FakeSource(email: null, applianceRead: (_) => const []),
      ).fetch(homeA);

      expect(result?.email, isNull);
      expect(result?.appliances, isEmpty);
      expect(result?.applianceCount, 0);
    },
  );

  test('rejects home absent from account and cross-home inventory', () async {
    await expectLater(
      SettingsDomainRepository(FakeSource(homesResult: [cloudHome(homeB)]))
          .fetch(homeA),
      throwsFormatException,
    );
    await expectLater(
      SettingsDomainRepository(
        FakeSource(applianceRead: (_) => [appliance(homeB, 'appliance-1')]),
      ).fetch(homeA),
      throwsFormatException,
    );
  });

  test('home switch and sign-out discard pending Settings responses', () async {
    final pendingHome = Completer<CloudVersioned<CloudHome>>();
    final repository = SettingsDomainRepository(
      FakeSource(
        homeRead: (id) => id == homeA
            ? pendingHome.future
            : Future.value(CloudVersioned(value: cloudHome(id), etag: '"2"')),
      ),
    );
    final oldFetch = repository.fetch(homeA);
    expect((await repository.fetch(homeB))?.home.id, homeB);
    pendingHome.complete(CloudVersioned(value: cloudHome(homeA), etag: '"1"'));
    expect(await oldFetch, isNull);

    final pending = Completer<CloudVersioned<CloudHome>>();
    final signedOutRepository = SettingsDomainRepository(
      FakeSource(homeRead: (_) => pending.future),
    );
    final signedOutFetch = signedOutRepository.fetch(homeA);
    signedOutRepository.clear();
    pending.complete(CloudVersioned(value: cloudHome(homeA), etag: '"1"'));
    expect(await signedOutFetch, isNull);
  });

  test('rejects invalid home IDs before making reads', () async {
    await expectLater(
      SettingsDomainRepository(FakeSource()).fetch('bad-id'),
      throwsArgumentError,
    );
  });
}
