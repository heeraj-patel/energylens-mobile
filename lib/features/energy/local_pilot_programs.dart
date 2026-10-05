import 'package:flutter/material.dart';

import 'stop_waste_programs.dart';

// Staged DOE source snapshot, observed 2026-10-05. Local pilot only.
const localPilotWapSourceSha256 =
    '05d32356150408fec895bc2751a369e20273abafa471e3e1fd959cab9bf4fc74';
const localPilotWapReviewExpiresAt = '2026-10-12T00:00:00Z';
final localPilotWapSourceUrl = Uri.parse(
  'https://www.energy.gov/cmei/scep/wap/how-apply-weatherization-assistance',
);

class LocalPilotPrograms extends StatelessWidget {
  const LocalPilotPrograms({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    if (!(now ?? DateTime.now()).isBefore(
      DateTime.parse(localPilotWapReviewExpiresAt),
    )) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ProgramOfferCard(
        key: const Key('localPilotWapProgram'),
        label: 'Federal',
        title: 'Weatherization Assistance Program',
        benefit: 'Weatherization services',
        sourceName: 'U.S. Department of Energy',
        sourceUrl: localPilotWapSourceUrl,
      ),
    );
  }
}
