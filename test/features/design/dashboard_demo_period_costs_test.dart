import 'package:energylens_mobile/features/design/dashboard_demo_period_costs.dart';
import 'package:energylens_mobile/features/design/dashboard_chart_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'approved device schedule aggregates five local day/week/month buckets',
    () {
      final day = DashboardDemoPeriodCosts.lastFive('day');
      expect(day.map((row) => row.startLocalDate.day), [26, 27, 28, 29, 30]);
      expect(day.map((row) => row.usefulCents), [400, 400, 400, 400, 696]);
      expect(day.map((row) => row.wasteCents), [56, 56, 56, 78, 288]);

      final week = DashboardDemoPeriodCosts.lastFive('week');
      expect(week.map((row) => row.startLocalDate.day), [31, 7, 14, 21, 28]);
      expect(week.map((row) => row.usefulCents), [
        2800,
        2800,
        2800,
        2800,
        1496,
      ]);
      expect(week.map((row) => row.wasteCents), [392, 392, 392, 392, 422]);

      final month = DashboardDemoPeriodCosts.lastFive('month');
      expect(month.map((row) => row.startLocalDate.month), [5, 6, 7, 8, 9]);
      expect(month.map((row) => row.usefulCents), [
        12400,
        12000,
        12400,
        12400,
        12296,
      ]);
      expect(month.map((row) => row.wasteCents), [
        1736,
        1680,
        1736,
        1736,
        1934,
      ]);
    },
  );

  test('fixture periods use the shared local calendar axis labels', () {
    expect(
      DashboardChartProjection.fromDemo('day').bars.map((bar) => bar.label),
      ['Sat', 'Sun', 'Mon', 'Tue', 'Wed'],
    );
    expect(
      DashboardChartProjection.fromDemo('week').bars.map((bar) => bar.label),
      ['Aug 31', 'Sep 7', 'Sep 14', 'Sep 21', 'Sep 28'],
    );
    expect(
      DashboardChartProjection.fromDemo('month').bars.map((bar) => bar.label),
      ['May', 'Jun', 'Jul', 'Aug', 'Sep'],
    );
  });
}
