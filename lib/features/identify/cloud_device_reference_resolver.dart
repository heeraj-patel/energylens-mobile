import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_catalog.dart';
import 'unresolved_device_help_report.dart';

enum DeviceReferenceStatus {
  resolved,
  noExactMatch,
  noReviewedFacts,
  lookupFailed,
}

enum DeviceReferenceMetric {
  annualKwh,
  standbyWatts,
  kwhPerCycle,
  kwhPerHour,
  ratedWatts,
}

/// A laboratory or manufacturer rating, never a measured household reading.
class DeviceReferenceFact {
  const DeviceReferenceFact({
    required this.metric,
    required this.value,
    required this.sourceKind,
    required this.sourceUrl,
    required this.testBasis,
    required this.reviewedAt,
  });

  final DeviceReferenceMetric metric;
  final double value;
  final String sourceKind;
  final Uri sourceUrl;
  final Map<String, dynamic> testBasis;
  final DateTime reviewedAt;
}

class DeviceReference {
  const DeviceReference({required this.productId, required this.facts});
  final String productId;
  final List<DeviceReferenceFact> facts;
}

class DeviceReferenceResolution {
  const DeviceReferenceResolution({
    required this.status,
    this.reference,
    this.reason,
  });

  final DeviceReferenceStatus status;
  final DeviceReference? reference;
  final String? reason;
  bool get isResolved => status == DeviceReferenceStatus.resolved;
}

/// Looks up a real appliance's exact KB-reviewed catalog rating.
/// Ratings are retained as evidence; classification needs separate evidence.
class CloudDeviceReferenceResolver {
  const CloudDeviceReferenceResolver(
    this.api, {
    this.helpReport,
    this.clock = DateTime.now,
  });

  final CloudApiClient api;
  final UnresolvedDeviceHelpReport? helpReport;
  final DateTime Function() clock;

  static const _sources = ['reviewed KB catalog'];

  Future<DeviceReferenceResolution> resolve(
    CloudAppliance appliance, {
    bool Function()? isCurrent,
  }) async {
    if (appliance.matchQuality != 'confirmed_exact' ||
        appliance.brand.trim().isEmpty ||
        appliance.fullModel.trim().isEmpty) {
      return _unresolved(
        appliance,
        DeviceReferenceStatus.noExactMatch,
        'Device identity is not confirmed exact.',
        const [],
        isCurrent,
      );
    }

    try {
      final products = <CloudCatalogProduct>[];
      if (appliance.catalogProductId case final productId?) {
        try {
          final linked = await api.catalogProduct(productId);
          products.add(linked);
          final reference = _referenceFor(appliance, linked);
          if (reference != null) {
            return DeviceReferenceResolution(
              status: DeviceReferenceStatus.resolved,
              reference: reference,
            );
          }
        } catch (_) {
          // A stale catalog link can still be recovered through model search.
        }
      }
      final search = await api.searchCatalogModels(
        brand: appliance.brand,
        model: appliance.fullModel,
        fuel: appliance.fuel,
        region: appliance.region,
      );
      for (final candidate in search) {
        if (products.any((product) => product.id == candidate.id)) continue;
        if (!_matches(appliance, candidate)) continue;
        products.add(await api.catalogProduct(candidate.id));
      }
      var matchedExact = false;
      for (final product in products) {
        if (!_matches(appliance, product)) continue;
        matchedExact = true;
        final reference = _referenceFor(appliance, product);
        if (reference != null) {
          return DeviceReferenceResolution(
            status: DeviceReferenceStatus.resolved,
            reference: reference,
          );
        }
      }
      return await _unresolved(
        appliance,
        matchedExact
            ? DeviceReferenceStatus.noReviewedFacts
            : DeviceReferenceStatus.noExactMatch,
        matchedExact
            ? 'Exact model has no supported KB-reviewed energy rating.'
            : 'No exact KB-reviewed model and variant matched.',
        _sources,
        isCurrent,
      );
    } catch (_) {
      return _unresolved(
        appliance,
        DeviceReferenceStatus.lookupFailed,
        'Reviewed catalog lookup was unavailable.',
        _sources,
        isCurrent,
      );
    }
  }

  static DeviceReference? _referenceFor(
    CloudAppliance appliance,
    CloudCatalogProduct product,
  ) {
    if (!_matches(appliance, product)) return null;
    final facts = product.facts
        .map(_reviewedFact)
        .whereType<DeviceReferenceFact>()
        .toList(growable: false);
    if (facts.isEmpty) return null;
    return DeviceReference(productId: product.id, facts: facts);
  }

  Future<DeviceReferenceResolution> _unresolved(
    CloudAppliance appliance,
    DeviceReferenceStatus status,
    String reason,
    List<String> sources,
    bool Function()? isCurrent,
  ) async {
    if (isCurrent == null || isCurrent()) {
      await helpReport?.append(
        appliance: appliance,
        reason: reason,
        lookupStatus: status.name,
        sourcesAttempted: sources,
        attemptedAt: clock(),
      );
    }
    return DeviceReferenceResolution(status: status, reason: reason);
  }

  static bool _matches(CloudAppliance appliance, CloudCatalogProduct product) {
    if (!product.isConfirmedExact || product.isDocumentedFamilyCandidate) {
      return false;
    }
    bool same(String a, String b) =>
        a.trim().toUpperCase() == b.trim().toUpperCase();
    bool sameOptional(String? a, String? b) =>
        a == null && b == null || a != null && b != null && same(a, b);
    return same(appliance.brand, product.brand) &&
        same(appliance.fullModel, product.fullModel) &&
        same(appliance.category, product.category) &&
        same(appliance.fuel, product.fuel) &&
        sameOptional(appliance.variant, product.variant) &&
        (appliance.region == null ||
            sameOptional(appliance.region, product.region));
  }

  static DeviceReferenceFact? _reviewedFact(CloudCatalogFact fact) {
    const metrics = <String, (String, DeviceReferenceMetric)>{
      'annual_energy': ('kWh', DeviceReferenceMetric.annualKwh),
      'standby_power': ('W', DeviceReferenceMetric.standbyWatts),
      'cycle_energy': ('kWh/cycle', DeviceReferenceMetric.kwhPerCycle),
      'hourly_energy': ('kWh/hour', DeviceReferenceMetric.kwhPerHour),
      'rated_power': ('W', DeviceReferenceMetric.ratedWatts),
    };
    final expected = metrics[fact.kind];
    final value = double.tryParse(fact.value);
    final url = Uri.tryParse(fact.sourceUrl);
    if (expected == null ||
        fact.unit != expected.$1 ||
        value == null ||
        !value.isFinite ||
        value <= 0 ||
        !const {
          'epa_exact',
          'energy_star_exact',
          'oem_exact',
          'other_official',
        }.contains(fact.sourceKind) ||
        url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty) {
      return null;
    }
    return DeviceReferenceFact(
      metric: expected.$2,
      value: value,
      sourceKind: fact.sourceKind,
      sourceUrl: url,
      testBasis: Map.unmodifiable(fact.testBasis),
      reviewedAt: fact.reviewedAt,
    );
  }
}
