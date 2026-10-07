import 'cloud_appliance.dart';

enum CloudApplianceDataMode { household, sample }

/// An appliance inventory response with its same-route source provenance.
///
/// Older callers can continue to use [CloudApiClient.appliances]; callers that
/// need to distinguish sample data should use [CloudApiClient.applianceList].
class CloudApplianceList {
  const CloudApplianceList({
    required this.appliances,
    required this.dataMode,
    required this.fixtureRevision,
    this.inventoryRevision,
  });

  final List<CloudAppliance> appliances;
  final CloudApplianceDataMode dataMode;
  final String? fixtureRevision;

  /// Opaque same-route change token. Absent on older servers.
  final String? inventoryRevision;

  bool get isSample => dataMode == CloudApplianceDataMode.sample;
}
