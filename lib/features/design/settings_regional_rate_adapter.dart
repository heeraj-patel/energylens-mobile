import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_preferences.dart';
import '../../core/cloud_api/cloud_regional_rate.dart';

abstract interface class SettingsRegionalRateSource {
  Future<CloudVersioned<CloudHome>> home(String homeId);
  Future<CloudRegionalRate> regionalRate(String country, String postalCode);
}

class CloudSettingsRegionalRateSource implements SettingsRegionalRateSource {
  const CloudSettingsRegionalRateSource(this.api);
  final CloudApiClient api;

  @override
  Future<CloudVersioned<CloudHome>> home(String homeId) => api.home(homeId);

  @override
  Future<CloudRegionalRate> regionalRate(String country, String postalCode) =>
      api.regionalElectricityRate(country: country, postalCode: postalCode);
}

/// Regional estimate and source metadata, separate from household tariffs.
class SettingsRegionalRateSnapshot {
  const SettingsRegionalRateSnapshot({
    required this.homeId,
    required this.countryCode,
    required this.postalCode,
    required this.regionalEstimate,
    required this.isCurrent,
  });

  final String homeId;
  final String countryCode;
  final String postalCode;
  final CloudRegionalRate? regionalEstimate;
  final bool Function() isCurrent;

  /// No household tariff is established by a public regional lookup.
  double? get householdTariffUsdPerKwh => null;
}

class SettingsRegionalRateAdapter {
  SettingsRegionalRateAdapter(this.source);
  final SettingsRegionalRateSource source;
  int _generation = 0;
  String? _homeId;

  void clear() {
    _generation++;
    _homeId = null;
  }

  Future<SettingsRegionalRateSnapshot?> fetch(String homeId) async {
    _homeId = homeId;
    final generation = ++_generation;
    bool stale() => generation != _generation || _homeId != homeId;
    try {
      final verified = (await source.home(homeId)).value;
      if (stale()) return null;
      if (verified.id.toLowerCase() != homeId.toLowerCase()) {
        throw const FormatException('Settings rate home changed');
      }
      final country = verified.countryCode;
      final postal = verified.postalCode;
      if (!RegExp(r'^[A-Z]{2}$').hasMatch(country) || postal.isEmpty) {
        throw const FormatException('Invalid Settings rate location');
      }
      CloudRegionalRate? rate;
      try {
        rate = await source.regionalRate(country, postal);
      } on CloudApiException catch (error) {
        if (error.statusCode != 404 || error.code != 'rate_unavailable') {
          rethrow;
        }
      }
      if (stale()) return null;
      return SettingsRegionalRateSnapshot(
        homeId: homeId,
        countryCode: country,
        postalCode: postal,
        regionalEstimate: rate,
        isCurrent: () => !stale(),
      );
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }
}
