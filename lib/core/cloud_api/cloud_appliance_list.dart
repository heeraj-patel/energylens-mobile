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
  });

  final List<CloudAppliance> appliances;
  final CloudApplianceDataMode dataMode;
  final String? fixtureRevision;

  bool get isSample => dataMode == CloudApplianceDataMode.sample;
}
