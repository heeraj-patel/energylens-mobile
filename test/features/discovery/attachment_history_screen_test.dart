import 'package:energylens_mobile/features/discovery/attachment_history_screen.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class HistoryApi extends DiscoveryApi {
  const HistoryApi();

  @override
  Future<List<AttachmentHistoryEntry>> attachmentHistory(
    String baseUrl,
    String token,
    String plugId,
  ) async => [
    AttachmentHistoryEntry.fromJson({
      'appliance_id': 2,
      'attached_at': 100,
      'detached_at': null,
      'snapshot_version': 1,
      'snapshot_recorded_at': 100,
      'appliance_snapshot': {
        'name': 'Desk lamp',
        'manufacturer': 'Acme',
        'model': 'L1',
        'hours_per_week': 21,
      },
      'estimate_snapshot': {
        'status': 'estimated',
        'estimated_kwh': 1.9838,
        'estimated_cost_usd': 0.315,
        'recorded_at': 120,
        'appliance_identity': {'manufacturer': 'Acme', 'model': 'L2'},
        'usage_inputs': {'usage_kind': 'hours_per_week', 'effective_value': 42},
        'evidence': {
          'source_kind': 'energy_star',
          'matched_brand': 'Acme',
          'matched_model': 'L1',
        },
      },
    }),
    AttachmentHistoryEntry.fromJson({
      'appliance_id': 1,
      'attached_at': 50,
      'detached_at': 100,
    }),
  ];
}

void main() {
  testWidgets('shows saved estimate and labels legacy history as unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AttachmentHistoryScreen(
          plug: const SavedPlug(
            id: 'plug-1',
            ip: '192.168.1.2',
            model: 'HS103',
            name: 'Office plug',
            room: 'Office',
            meterStatus: 'absent',
            lastVerifiedAt: 100,
          ),
          api: const HistoryApi(),
          hubAddress: 'https://hub.test',
          token: 'token',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved estimate: 1.98 kWh/month'), findsOneWidget);
    expect(find.text('Saved cost estimate: \$0.32/month'), findsOneWidget);
    expect(find.text('Attached as: Acme L1'), findsOneWidget);
    expect(find.text('Estimate for Acme L2'), findsOneWidget);
    expect(find.text('Usage at attachment: 21 hours/week'), findsOneWidget);
    expect(find.text('Usage for estimate: 42 hours/week'), findsOneWidget);
    expect(find.textContaining('Source:'), findsNothing);
    expect(find.textContaining('Rate:'), findsNothing);
    expect(
      find.text(
        'This older attachment has no saved identity or estimate snapshot.',
      ),
      findsOneWidget,
    );
  });
}
