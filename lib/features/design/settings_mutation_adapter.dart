import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_preferences.dart';
import 'settings_domain_repository.dart';

/// The only Settings writes currently supported by the owner cloud API.
abstract interface class SettingsMutationSource
    implements SettingsDomainSource {
  Future<CloudVersioned<CloudHome>> updateHome(
    String homeId,
    CloudHomePatch patch, {
    required String ifMatch,
    required String idempotencyKey,
  });
  Future<CloudVersioned<CloudAccountPreferences>> updateAccountPreferences(
    Map<String, dynamic> patch, {
    required String ifMatch,
    required String idempotencyKey,
  });
  Future<CloudVersioned<CloudHomePreferences>> updateHomePreferences(
    String homeId,
    CloudHomePreferences preferences, {
    required String ifMatch,
    required String idempotencyKey,
  });
}

class CloudSettingsMutationSource extends CloudSettingsDomainSource
    implements SettingsMutationSource {
  const CloudSettingsMutationSource(super.api);

  @override
  Future<CloudVersioned<CloudHome>> updateHome(
    String homeId,
    CloudHomePatch patch, {
    required String ifMatch,
    required String idempotencyKey,
  }) => api.updateHome(
    homeId,
    patch,
    ifMatch: ifMatch,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<CloudVersioned<CloudAccountPreferences>> updateAccountPreferences(
    Map<String, dynamic> patch, {
    required String ifMatch,
    required String idempotencyKey,
  }) => api.updateAccountPreferences(
    patch,
    ifMatch: ifMatch,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<CloudVersioned<CloudHomePreferences>> updateHomePreferences(
    String homeId,
    CloudHomePreferences preferences, {
    required String ifMatch,
    required String idempotencyKey,
  }) => api.updateHomePreferences(
    homeId,
    preferences,
    ifMatch: ifMatch,
    idempotencyKey: idempotencyKey,
  );
}

/// Holds one account/home context. Call clear on sign-out and load on a switch.
/// A returned null means the response was superseded by another context.
class SettingsMutationAdapter {
  SettingsMutationAdapter(this.source)
    : _reads = SettingsDomainRepository(source);

  final SettingsMutationSource source;
  final SettingsDomainRepository _reads;
  SettingsDomainSnapshot? _snapshot;
  int _generation = 0;
  int? _writingGeneration;
  String? _lastHomeTimezoneResolution;

  SettingsDomainSnapshot? get snapshot => _snapshot;
  String? get lastHomeTimezoneResolution => _lastHomeTimezoneResolution;

  void clear() {
    _generation++;
    _snapshot = null;
    _writingGeneration = null;
    _lastHomeTimezoneResolution = null;
    _reads.clear();
  }

  Future<SettingsDomainSnapshot?> load(String homeId) async {
    clear();
    final generation = _generation;
    final result = await _reads.fetch(homeId);
    if (generation != _generation) return null;
    _snapshot = result;
    return result;
  }

  Future<SettingsDomainSnapshot?> updateHome(
    CloudHomePatch patch, {
    required String idempotencyKey,
  }) async {
    final fields = patch.toJson();
    _lastHomeTimezoneResolution = null;
    return _write(
      idempotencyKey,
      (before) => source.updateHome(
        before.home.id,
        patch,
        ifMatch: _etag(before.homeEtag),
        idempotencyKey: idempotencyKey,
      ),
      (before, response, after) {
        final updated = response as CloudVersioned<CloudHome>;
        if (updated.value.id != before.home.id ||
            after.homeEtag != updated.etag ||
            after.home.version != updated.value.version ||
            (fields.containsKey('name') && after.home.name != fields['name']) ||
            (fields.containsKey('timezone') &&
                after.home.timezone != fields['timezone']) ||
            (fields.containsKey('location') &&
                (after.home.countryCode != patch.countryCode ||
                    after.home.postalCode != patch.postalCode))) {
          throw const FormatException('Home readback differs from update');
        }
        _lastHomeTimezoneResolution = updated.value.timezoneResolution;
      },
    );
  }

  Future<SettingsDomainSnapshot?> updateEmailReportsEnabled(
    bool enabled, {
    required String idempotencyKey,
  }) => _write(
    idempotencyKey,
    (before) => source.updateAccountPreferences(
      {'email_reports_enabled': enabled},
      ifMatch: _etag(before.accountPreferencesEtag),
      idempotencyKey: idempotencyKey,
    ),
    (before, response, after) {
      final updated = response as CloudVersioned<CloudAccountPreferences>;
      if (after.accountPreferencesEtag != updated.etag ||
          after.accountPreferences.version != updated.value.version ||
          after.emailReportsEnabled != enabled) {
        throw const FormatException(
          'Account preferences readback differs from update',
        );
      }
    },
  );

  Future<SettingsDomainSnapshot?> updateHomePreferences({
    required String goal,
    required String comfortPriority,
    required String idempotencyKey,
  }) {
    if (!CloudHomePreferences.goals.contains(goal) ||
        !CloudHomePreferences.comfortPriorities.contains(comfortPriority)) {
      throw ArgumentError('Invalid home preferences');
    }
    return _write(
      idempotencyKey,
      (before) => source.updateHomePreferences(
        before.home.id,
        CloudHomePreferences(
          version: before.homePreferences.version,
          goal: goal,
          comfortPriority: comfortPriority,
        ),
        ifMatch: _etag(before.homePreferencesEtag),
        idempotencyKey: idempotencyKey,
      ),
      (before, response, after) {
        final updated = response as CloudVersioned<CloudHomePreferences>;
        if (after.homePreferencesEtag != updated.etag ||
            after.homePreferences.version != updated.value.version ||
            after.homePreferences.goal != goal ||
            after.homePreferences.comfortPriority != comfortPriority) {
          throw const FormatException(
            'Home preferences readback differs from update',
          );
        }
      },
    );
  }

  Future<SettingsDomainSnapshot?> _write(
    String idempotencyKey,
    Future<Object> Function(SettingsDomainSnapshot) send,
    void Function(SettingsDomainSnapshot, Object, SettingsDomainSnapshot) check,
  ) async {
    if (_writingGeneration == _generation) {
      throw StateError('Settings update already in progress');
    }
    final before = _snapshot;
    if (before == null) {
      throw StateError('Load account and home before updating');
    }
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(idempotencyKey)) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey');
    }
    final generation = _generation;
    bool stale() => generation != _generation;
    _writingGeneration = generation;
    try {
      final account = await source.account();
      final homes = await source.homes();
      if (stale()) return null;
      if (account.id != before.account.id ||
          !homes.any((home) => home.id == before.home.id)) {
        throw const FormatException('Settings account or home scope changed');
      }
      final response = await send(before);
      if (stale()) return null;
      final after = await _reads.fetch(before.home.id);
      if (stale() || after == null) return null;
      if (after.account.id != before.account.id ||
          after.home.id != before.home.id) {
        throw const FormatException('Settings context changed during update');
      }
      check(before, response, after);
      _snapshot = after;
      return after;
    } catch (_) {
      if (stale()) return null;
      clear();
      rethrow;
    } finally {
      if (_writingGeneration == generation) {
        _writingGeneration = null;
      }
    }
  }

  static String _etag(String etag) {
    if (!RegExp(r'^"[1-9][0-9]*"$').hasMatch(etag)) {
      throw const FormatException('Missing strong version ETag');
    }
    return etag;
  }
}
