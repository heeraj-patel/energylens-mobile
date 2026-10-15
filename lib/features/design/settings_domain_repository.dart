import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_preferences.dart';

/// Typed reads used to build Settings data without coupling it to a renderer.
abstract interface class SettingsDomainSource {
  Future<CloudAccount> account();
  Future<List<CloudHome>> homes();
  Future<CloudVersioned<CloudAccountPreferences>> accountPreferences();
  Future<CloudVersioned<CloudHome>> home(String homeId);
  Future<CloudVersioned<CloudHomePreferences>> homePreferences(String homeId);
  Future<List<CloudAppliance>> appliances(String homeId);
}

class CloudSettingsDomainSource implements SettingsDomainSource {
  const CloudSettingsDomainSource(this.api);
  final CloudApiClient api;

  @override
  Future<CloudAccount> account() => api.me();
  @override
  Future<List<CloudHome>> homes() => api.homes();
  @override
  Future<CloudVersioned<CloudAccountPreferences>> accountPreferences() =>
      api.accountPreferences();
  @override
  Future<CloudVersioned<CloudHome>> home(String homeId) => api.home(homeId);
  @override
  Future<CloudVersioned<CloudHomePreferences>> homePreferences(String homeId) =>
      api.homePreferences(homeId);
  @override
  Future<List<CloudAppliance>> appliances(String homeId) =>
      api.appliances(homeId);
}

/// A read-only account/home snapshot for Settings.
///
/// Profile display fields come from Cloud; credentials never enter this model.
class SettingsDomainSnapshot {
  const SettingsDomainSnapshot({
    required this.account,
    required this.homes,
    required this.accountPreferences,
    required this.accountPreferencesEtag,
    required this.home,
    required this.homeEtag,
    required this.homePreferences,
    required this.homePreferencesEtag,
    required this.appliances,
  });

  final CloudAccount account;
  final List<CloudHome> homes;
  final CloudAccountPreferences accountPreferences;
  final String accountPreferencesEtag;
  final CloudHome home;
  final String homeEtag;
  final CloudHomePreferences homePreferences;
  final String homePreferencesEtag;
  final List<CloudAppliance> appliances;

  String? get email => account.email;
  String? get identity => account.authMethod == 'username_password'
      ? account.username
      : account.email;
  bool get usernameIdentity => account.authMethod == 'username_password';
  bool get emailVerified => account.emailVerified;
  String get homeName => home.name;
  String get postalCode => home.postalCode;
  String get timezone => home.timezone;
  bool get emailReportsEnabled => accountPreferences.emailReportsEnabled;
  int get applianceCount => appliances.length;

  String? get accountOwner => account.displayName;
}

/// Drops pending responses when another home is requested or the session ends.
class SettingsDomainRepository {
  SettingsDomainRepository(this.source);
  final SettingsDomainSource source;
  String? _homeId;
  int _generation = 0;

  void clear() {
    _homeId = null;
    _generation++;
  }

  Future<SettingsDomainSnapshot?> fetch(String homeId) async {
    if (!_uuid.hasMatch(homeId)) throw ArgumentError.value(homeId, 'homeId');
    _homeId = homeId;
    final generation = ++_generation;
    bool stale() => generation != _generation || _homeId != homeId;
    try {
      final accountAndHomes = await Future.wait<Object>([
        source.account(),
        source.homes(),
        source.accountPreferences(),
      ]);
      if (stale()) return null;
      final homes = accountAndHomes[1] as List<CloudHome>;
      _validateHomes(homes);
      if (!homes.any((home) => home.id == homeId)) {
        throw const FormatException('Selected home is not in account homes');
      }
      final homeData = await Future.wait<Object>([
        source.home(homeId),
        source.homePreferences(homeId),
        source.appliances(homeId),
      ]);
      if (stale()) return null;
      final home = homeData[0] as CloudVersioned<CloudHome>;
      final homePreferences =
          homeData[1] as CloudVersioned<CloudHomePreferences>;
      final appliances = homeData[2] as List<CloudAppliance>;
      if (home.value.id != homeId ||
          appliances.any((item) => item.homeId != homeId)) {
        throw const FormatException('Settings reads belong to different homes');
      }
      _validateUniqueAppliances(appliances);
      return SettingsDomainSnapshot(
        account: accountAndHomes[0] as CloudAccount,
        homes: List.unmodifiable(homes),
        accountPreferences:
            (accountAndHomes[2] as CloudVersioned<CloudAccountPreferences>)
                .value,
        accountPreferencesEtag:
            (accountAndHomes[2] as CloudVersioned<CloudAccountPreferences>)
                .etag,
        home: home.value,
        homeEtag: home.etag,
        homePreferences: homePreferences.value,
        homePreferencesEtag: homePreferences.etag,
        appliances: List.unmodifiable(appliances),
      );
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

void _validateHomes(List<CloudHome> homes) {
  final ids = <String>{};
  for (final home in homes) {
    if (!ids.add(home.id)) throw const FormatException('Duplicate home');
  }
}

void _validateUniqueAppliances(List<CloudAppliance> appliances) {
  final ids = <String>{};
  for (final appliance in appliances) {
    if (!ids.add(appliance.id)) {
      throw const FormatException('Duplicate appliance');
    }
  }
}
