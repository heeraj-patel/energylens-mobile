import 'demo_energy_projection.dart';
import 'demo_energy_tree.dart';

/// Internal links from the display tree to FAQ questions. These are
/// illustrative facts, not verified evidence or customer answer text.
sealed class KnowledgeMockFaqFact {
  const KnowledgeMockFaqFact(this.questionId, this.homeId, this.period);

  final String questionId;
  final String homeId;
  final DemoDayPeriod period;
  DemoValueOrigin get origin => DemoValueOrigin.mock;
}

class KnowledgeMockHomeCosts extends KnowledgeMockFaqFact {
  const KnowledgeMockHomeCosts(
    super.questionId,
    super.homeId,
    super.period, {
    required this.home,
    required this.devices,
    required this.unattributed,
  });

  final DemoCost home;
  final DemoCost devices;
  final DemoCost unattributed;
}

class KnowledgeMockDeviceList extends KnowledgeMockFaqFact {
  KnowledgeMockDeviceList(
    super.questionId,
    super.homeId,
    super.period,
    List<DemoBranch> devices,
  ) : devices = List.unmodifiable(devices);

  final List<DemoBranch> devices;
}

class KnowledgeMockDeviceCost extends KnowledgeMockFaqFact {
  const KnowledgeMockDeviceCost(
    super.questionId,
    super.homeId,
    super.period,
    this.device,
  );

  final DemoBranch device;
}

/// Returns only the mock facts actually present for the selected home and
/// local day. Catalog publication and answer rendering remain separate gates.
class KnowledgeMockFaqLinkage {
  const KnowledgeMockFaqLinkage(this.projection);

  final DemoEnergyProjection projection;

  KnowledgeMockFaqFact? forQuestion({
    required String questionId,
    required String selectedHomeId,
    required String localDate,
    String? selectedDeviceId,
  }) {
    if (projection.homeId.toLowerCase() != selectedHomeId.toLowerCase() ||
        projection.referenceLocalDate != localDate ||
        projection.referenceDay.period.localDate != localDate) {
      return null;
    }
    final day = projection.referenceDay;
    switch (questionId) {
      case 'home_vs_devices':
      case 'useful_waste_meaning':
      case 'unknown_cost_meaning':
        if (selectedDeviceId != null ||
            day.unattributed.origin != DemoValueOrigin.mock ||
            day.devices.any(
              (device) => device.origin != DemoValueOrigin.mock,
            )) {
          return null;
        }
        return KnowledgeMockHomeCosts(
          questionId,
          day.homeId,
          day.period,
          home: day.homeCost,
          devices: day.devicesCost,
          unattributed: day.unattributed.cost,
        );
      case 'device_inventory':
        if (selectedDeviceId != null) return null;
        return KnowledgeMockDeviceList(
          questionId,
          day.homeId,
          day.period,
          day.devices
              .where((device) => device.origin == DemoValueOrigin.mock)
              .toList(),
        );
      case 'device_cost':
        if (selectedDeviceId == null) return null;
        for (final device in day.devices) {
          if (device.deviceId == selectedDeviceId &&
              device.origin == DemoValueOrigin.mock) {
            return KnowledgeMockDeviceCost(
              questionId,
              day.homeId,
              day.period,
              device,
            );
          }
        }
        return null;
      default:
        return null;
    }
  }
}
