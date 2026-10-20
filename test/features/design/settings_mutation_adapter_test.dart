import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_preferences.dart';
import 'package:energylens_mobile/features/design/settings_mutation_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';
const keyA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const keyB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

class FakeSource implements SettingsMutationSource {
  String accountId = 'owner';
  String name = 'Home';
  String postalCode = '60601';
  String timezone = 'America/Chicago';
  int homeVersion = 1;
  int accountVersion = 1;
  int preferencesVersion = 1;
  bool emailReports = true;
  String goal = 'unspecified';
  String comfort = 'unknown';
  bool crossHomeRead = false;
  bool staleReadback = false;
  Completer<CloudVersioned<CloudHome>>? pendingPatch;
  final Map<String, CloudVersioned<CloudHome>> completedHomeWrites = {};
  int homePatchCount = 0;
  String? lastIfMatch;

  CloudHome _home(
    String id, {
    String? value,
    int? version,
    String? timezoneResolution,
  }) => CloudHome(
    id: id,
    name: value ?? name,
    timezone: timezone,
    countryCode: 'US',
    postalCode: postalCode,
    timezoneResolution: timezoneResolution,
    version: version ?? homeVersion,
  );

  @override
  Future<CloudAccount> account() async =>
      CloudAccount(id: accountId, email: null, emailVerified: false);
  @override
  Future<List<CloudHome>> homes() async => [_home(homeA), _home(homeB)];
  @override
  Future<CloudVersioned<CloudAccountPreferences>> accountPreferences() async =>
      CloudVersioned(
        value: CloudAccountPreferences(
          version: accountVersion,
          emailReportsEnabled: emailReports,
        ),
        etag: '"$accountVersion"',
      );
  @override
  Future<CloudVersioned<CloudHome>> home(String homeId) async => CloudVersioned(
    value: _home(
      crossHomeRead ? homeB : homeId,
      value: staleReadback ? 'Home' : name,
      version: staleReadback ? 1 : homeVersion,
    ),
    etag: '"${staleReadback ? 1 : homeVersion}"',
  );
  @override
  Future<CloudVersioned<CloudHomePreferences>> homePreferences(
    String homeId,
  ) async => CloudVersioned(
    value: CloudHomePreferences(
      version: preferencesVersion,
      goal: goal,
      comfortPriority: comfort,
    ),
    etag: '"$preferencesVersion"',
  );
  @override
  Future<List<CloudAppliance>> appliances(String homeId) async => [];

  @override
  Future<CloudVersioned<CloudHome>> updateHome(
    String homeId,
    CloudHomePatch patch, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    homePatchCount++;
    lastIfMatch = ifMatch;
    if (completedHomeWrites.containsKey(idempotencyKey)) {
      return completedHomeWrites[idempotencyKey]!;
    }
    if (homeId != homeA || ifMatch != '"$homeVersion"') {
      throw const CloudApiException(409, 'version_conflict');
    }
    if (pendingPatch != null) return pendingPatch!.future;
    name = patch.name ?? name;
    String? resolution;
    if (patch.postalCode != null) {
      postalCode = patch.postalCode!;
      resolution = postalCode == '94107' ? 'resolved' : 'unresolved';
      if (resolution == 'resolved') timezone = 'America/Los_Angeles';
    }
    homeVersion++;
    final result = CloudVersioned(
      value: _home(homeId, timezoneResolution: resolution),
      etag: '"$homeVersion"',
    );
    completedHomeWrites[idempotencyKey] = result;
    return result;
  }

  @override
  Future<CloudVersioned<CloudAccountPreferences>> updateAccountPreferences(
    Map<String, dynamic> patch, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    if (ifMatch != '"$accountVersion"') {
      throw const CloudApiException(409, 'version_conflict');
    }
    emailReports = patch['email_reports_enabled'] as bool;
    accountVersion++;
    return accountPreferences();
  }

  @override
  Future<CloudVersioned<CloudHomePreferences>> updateHomePreferences(
    String homeId,
    CloudHomePreferences preferences, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    if (homeId != homeA || ifMatch != '"$preferencesVersion"') {
      throw const CloudApiException(409, 'version_conflict');
    }
    goal = preferences.goal;
    comfort = preferences.comfortPriority;
    preferencesVersion++;
    return homePreferences(homeId);
  }
}

void main() {
  test('ZIP readback carries derived zone and unresolved status', () async {
    final source = FakeSource();
    final adapter = SettingsMutationAdapter(source);
    await adapter.load(homeA);
    final resolved = await adapter.updateHome(
      const CloudHomePatch(countryCode: 'US', postalCode: '94107'),
      idempotencyKey: keyA,
    );
    expect(resolved?.timezone, 'America/Los_Angeles');
    expect(adapter.lastHomeTimezoneResolution, 'resolved');
    final unresolved = await adapter.updateHome(
      const CloudHomePatch(countryCode: 'US', postalCode: '85001'),
      idempotencyKey: keyB,
    );
    expect(unresolved?.timezone, 'America/Los_Angeles');
    expect(adapter.lastHomeTimezoneResolution, 'unresolved');
  });

  test(
    'home and preference mutations return fresh versioned readback',
    () async {
      final source = FakeSource();
      final adapter = SettingsMutationAdapter(source);
      await adapter.load(homeA);
      final home = await adapter.updateHome(
        const CloudHomePatch(name: 'Updated'),
        idempotencyKey: keyA,
      );
      expect(source.lastIfMatch, '"1"');
      expect(home?.homeName, 'Updated');
      expect(home?.homeEtag, '"2"');
      expect(
        (await adapter.updateEmailReportsEnabled(
          false,
          idempotencyKey: keyB,
        ))?.emailReportsEnabled,
        false,
      );
      expect(
        (await adapter.updateHomePreferences(
          goal: 'reduce_cost',
          comfortPriority: 'balanced',
          idempotencyKey: keyA,
        ))?.homePreferences.goal,
        'reduce_cost',
      );
    },
  );

  test('stale version conflict clears context and requires reload', () async {
    final source = FakeSource();
    final adapter = SettingsMutationAdapter(source);
    await adapter.load(homeA);
    source.homeVersion++;
    await expectLater(
      adapter.updateHome(
        const CloudHomePatch(name: 'Changed'),
        idempotencyKey: keyA,
      ),
      throwsA(
        isA<CloudApiException>().having((e) => e.statusCode, 'status', 409),
      ),
    );
    expect(adapter.snapshot, isNull);
    await expectLater(
      adapter.updateHome(
        const CloudHomePatch(name: 'Changed'),
        idempotencyKey: keyB,
      ),
      throwsStateError,
    );
  });

  test(
    'duplicate retry reuses the idempotency key and reads current state',
    () async {
      final source = FakeSource();
      final first = SettingsMutationAdapter(source);
      final retry = SettingsMutationAdapter(source);
      await first.load(homeA);
      await retry.load(homeA);
      await first.updateHome(
        const CloudHomePatch(name: 'Updated'),
        idempotencyKey: keyA,
      );
      final result = await retry.updateHome(
        const CloudHomePatch(name: 'Updated'),
        idempotencyKey: keyA,
      );
      expect(result?.homeName, 'Updated');
      expect(source.homePatchCount, 2);
      expect(source.homeVersion, 2);
    },
  );

  test('cross-home and stale readback are rejected', () async {
    final source = FakeSource();
    final adapter = SettingsMutationAdapter(source);
    await adapter.load(homeA);
    source.crossHomeRead = true;
    await expectLater(
      adapter.updateHome(
        const CloudHomePatch(name: 'Updated'),
        idempotencyKey: keyA,
      ),
      throwsFormatException,
    );
    expect(adapter.snapshot, isNull);

    source.crossHomeRead = false;
    await adapter.load(homeA);
    source.staleReadback = true;
    await expectLater(
      adapter.updateHome(
        const CloudHomePatch(name: 'Again'),
        idempotencyKey: keyB,
      ),
      throwsFormatException,
    );
    expect(adapter.snapshot, isNull);
  });

  test(
    'account change before write cannot reuse prior account context',
    () async {
      final source = FakeSource();
      final adapter = SettingsMutationAdapter(source);
      await adapter.load(homeA);
      source.accountId = 'different-owner';
      await expectLater(
        adapter.updateHome(
          const CloudHomePatch(name: 'Updated'),
          idempotencyKey: keyA,
        ),
        throwsFormatException,
      );
      expect(source.homePatchCount, 0);
      expect(adapter.snapshot, isNull);
    },
  );

  test(
    'home switch and sign-out discard in-flight mutation responses',
    () async {
      final source = FakeSource();
      final adapter = SettingsMutationAdapter(source);
      await adapter.load(homeA);
      source.pendingPatch = Completer<CloudVersioned<CloudHome>>();
      final old = adapter.updateHome(
        const CloudHomePatch(name: 'Old'),
        idempotencyKey: keyA,
      );
      await adapter.load(homeB);
      source.pendingPatch!.complete(
        CloudVersioned(value: source._home(homeA), etag: '"1"'),
      );
      expect(await old, isNull);
      expect(adapter.snapshot?.home.id, homeB);
      await adapter.load(homeA);
      source.pendingPatch = Completer<CloudVersioned<CloudHome>>();
      final signedOut = adapter.updateHome(
        const CloudHomePatch(name: 'Signed out'),
        idempotencyKey: keyB,
      );
      adapter.clear();
      source.pendingPatch!.complete(
        CloudVersioned(value: source._home(homeA), etag: '"1"'),
      );
      expect(await signedOut, isNull);
      expect(adapter.snapshot, isNull);
    },
  );
}
