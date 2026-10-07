import 'cloud_appliance.dart';
import 'cloud_appliance_list.dart';

/// A single appliance read with its validator and same-route source metadata.
class CloudApplianceDetail {
  const CloudApplianceDetail({
    required this.appliance,
    required this.etag,
    required this.dataMode,
    required this.fixtureRevision,
  });

  final CloudAppliance appliance;
  final String etag;
  final CloudApplianceDataMode dataMode;
  final String? fixtureRevision;

  bool get isSample => dataMode == CloudApplianceDataMode.sample;
}
