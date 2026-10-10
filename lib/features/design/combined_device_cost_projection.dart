import '../../core/cloud_api/cloud_household_energy.dart';

/// Returns the demo-plus-real attributed cost for a mixed household trends
/// response. In mixed history mode, the home total contains real cost while
/// demo allocations remain separate. The result is only available when the
/// real per-device rows reconcile to every bucket's real home cost.
CloudEnergyMoney? combinedMixedDeviceCost(CloudHouseholdEnergyTrends trends) {
  if (trends.dataMode != 'mixed' ||
      trends.fixtureRevision == null ||
      trends.contentRevision == trends.fixtureRevision) {
    return null;
  }

  var realTotal = BigInt.zero;
  var demoTotal = BigInt.zero;
  for (final bucket in trends.buckets) {
    final realRows = <String>{};
    final demoRows = <String>{};
    var realBucket = BigInt.zero;
    var demoBucket = BigInt.zero;
    for (final row in bucket.deviceAllocations) {
      final id = (row.applianceId ?? row.deviceId)?.toLowerCase();
      if (id == null) return null;
      final cost = _moneyUnits(row.allocation.cost);
      if (cost == null ||
          row.allocation.availability == 'unavailable' ||
          row.allocation.evidenceBasis == 'unavailable') {
        return null;
      }
      if (row.deviceId != null) {
        if (!demoRows.add(id)) return null;
        demoBucket += cost;
      } else {
        if (!realRows.add(id)) return null;
        realBucket += cost;
      }
    }
    final realHomeCost = _moneyUnits(bucket.allocation.cost);
    if (realHomeCost == null || realBucket != realHomeCost) return null;
    realTotal += realBucket;
    demoTotal += demoBucket;
  }

  final reportedRealTotal = _moneyUnits(trends.totals.cost);
  if (reportedRealTotal == null || realTotal != reportedRealTotal) return null;
  final combinedUnits = realTotal + demoTotal;
  return CloudEnergyMoney(
    amount: _unitsToDecimal(combinedUnits),
    currency: 'USD',
  );
}

BigInt? _moneyUnits(CloudEnergyMoney? value) {
  if (value == null ||
      value.currency != 'USD' ||
      !RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,8})?$').hasMatch(value.amount)) {
    return null;
  }
  final parts = value.amount.split('.');
  return BigInt.parse(parts[0]) * BigInt.from(100000000) +
      BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(8, '0'));
}

String _unitsToDecimal(BigInt units) {
  final whole = units ~/ BigInt.from(100000000);
  final fraction = (units % BigInt.from(100000000))
      .toString()
      .padLeft(8, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}
