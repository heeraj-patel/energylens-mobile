import 'dart:async';

import 'package:flutter/material.dart';

import 'features/discovery/discovery_screen.dart';
import 'features/discovery/discovery_api.dart';
import 'features/discovery/discovery_credentials.dart';
import 'features/discovery/electricity_settings_screen.dart';
import 'features/identify/appliance_onboarding_screen.dart';

void main() => runApp(const EnergyLensApp());

const _green = Color(0xFF008F68);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF61738B);
const _rose = Color(0xFFE11D48);
const _line = Color(0xFFE1E8EE);

String _sampleTime(DateTime ts) {
  final utc = ts.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return 'sampled ${utc.year}-${two(utc.month)}-${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)} UTC';
}

class EnergyLensApp extends StatelessWidget {
  const EnergyLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) {
      final dark = brightness == Brightness.dark;
      final scheme = ColorScheme.fromSeed(
        seedColor: _green,
        brightness: brightness,
      );
      return ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: dark
            ? const Color(0xFF101B2D)
            : const Color(0xFFF8FAFC),
        appBarTheme: AppBarTheme(
          backgroundColor: dark ? const Color(0xFF172337) : Colors.white,
          foregroundColor: dark ? Colors.white : _ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: dark ? const Color(0xFF1D2A3D) : Colors.white,
          elevation: 1,
          shadowColor: const Color(0x141C4761),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: dark ? const Color(0xFF354558) : _line),
            borderRadius: BorderRadius.circular(22),
          ),
          margin: EdgeInsets.zero,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: dark ? const Color(0xFF172337) : Colors.white,
          indicatorColor: dark
              ? const Color(0xFF174A42)
              : const Color(0xFFE3F5ED),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(
              fontWeight: FontWeight.w600,
              color: dark ? Colors.white : _ink,
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'EnergyLens',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
  });

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;
  bool _hubConnected = false;
  List<SavedPlug> _plugs = const [];
  Map<int, EnergyEstimate> _estimates = const {};
  Map<String, DeviceEnergy> _meterReadings = const {};
  int _refreshGeneration = 0;
  int _meterGeneration = 0;
  Timer? _meterRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshHub();
    _meterRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_refreshConnectivityAndMetering()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _meterRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshHub();
  }

  Future<void> _refreshHub() async {
    final generation = ++_refreshGeneration;
    try {
      final (address, token) = await widget.credentials.read();
      if (address == null || token == null) {
        if (mounted && generation == _refreshGeneration) {
          setState(() {
            _hubConnected = false;
            _meterReadings = const {};
            ++_meterGeneration;
          });
        }
        return;
      }
      final plugs = await widget.api.saved(address, token);
      if (mounted && generation == _refreshGeneration) {
        setState(() {
          _plugs = plugs;
          _hubConnected = true;
          _estimates = const {};
          _meterReadings = const {};
        });
      }
      unawaited(_refreshMetering(plugs: plugs, address: address, token: token));
      await Future.wait([
        for (final plug in plugs)
          if (plug.connectedAppliance case final appliance?)
            () async {
              try {
                final estimate = await widget.api.estimate(
                  address,
                  token,
                  appliance.id,
                );
                if (mounted && generation == _refreshGeneration) {
                  setState(
                    () => _estimates = {..._estimates, appliance.id: estimate},
                  );
                }
              } catch (_) {
                // One unavailable estimate must not hide the saved plug.
              }
            }(),
      ]);
    } catch (_) {
      if (mounted && generation == _refreshGeneration) {
        setState(() {
          _hubConnected = false;
          _meterReadings = const {};
          ++_meterGeneration;
        });
      }
    }
  }

  Future<void> _refreshConnectivityAndMetering() async {
    final generation = ++_refreshGeneration;
    try {
      final (address, token) = await widget.credentials.read();
      if (address == null || token == null) {
        if (mounted && generation == _refreshGeneration) {
          setState(() {
            _hubConnected = false;
            _meterReadings = const {};
            ++_meterGeneration;
          });
        }
        return;
      }
      final plugs = await widget.api.saved(address, token);
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _hubConnected = true;
        _plugs = plugs;
      });
      await _refreshMetering(plugs: plugs, address: address, token: token);
    } catch (_) {
      if (mounted && generation == _refreshGeneration) {
        setState(() {
          _hubConnected = false;
          _meterReadings = const {};
          ++_meterGeneration;
        });
      }
    }
  }

  Future<void> _refreshMetering({
    List<SavedPlug>? plugs,
    String? address,
    String? token,
  }) async {
    final generation = ++_meterGeneration;
    try {
      if (address == null || token == null) {
        (address, token) = await widget.credentials.read();
      }
      if (address == null || token == null) return;
      final candidates = plugs ?? _plugs;
      await Future.wait([
        for (final plug in candidates)
          if (plug.meterStatus != 'absent' &&
              const {
                'legacy_tcp',
                'shelly_gen2',
                'tasmota',
              }.contains(plug.localProtocol))
            () async {
              try {
                final reading = await widget.api.deviceEnergy(
                  address!,
                  token!,
                  plug.id,
                );
                if (mounted && generation == _meterGeneration) {
                  setState(
                    () =>
                        _meterReadings = {..._meterReadings, plug.id: reading},
                  );
                }
              } catch (_) {
                if (mounted && generation == _meterGeneration) {
                  setState(() {
                    final next = {..._meterReadings};
                    next.remove(plug.id);
                    _meterReadings = next;
                  });
                }
              }
            }(),
      ]);
    } catch (_) {
      // A meter API failure must not hide saved plugs or sourced estimates.
    }
  }

  Future<void> _saveApplianceHours(int applianceId, double hoursPerWeek) async {
    final (address, token) = await widget.credentials.read();
    if (address == null || token == null) {
      throw StateError('Hub connection needed');
    }
    await widget.api.updateApplianceHours(
      address,
      token,
      applianceId,
      hoursPerWeek,
    );
    await _refreshHub();
  }

  Future<ApplianceUsageProfile> _loadApplianceUsage(int applianceId) async {
    final (address, token) = await widget.credentials.read();
    if (address == null || token == null) {
      throw StateError('Hub connection needed');
    }
    return widget.api.applianceUsageProfile(address, token, applianceId);
  }

  Future<ApplianceUsageProfile> _saveApplianceUsage(
    int applianceId,
    String usageKind,
    double value,
  ) async {
    final (address, token) = await widget.credentials.read();
    if (address == null || token == null) {
      throw StateError('Hub connection needed');
    }
    final saved = await widget.api.updateApplianceUsageProfile(
      address,
      token,
      applianceId,
      usageKind,
      value,
    );
    await _refreshHub();
    return saved;
  }

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.bolt_outlined),
      selectedIcon: Icon(Icons.bolt),
      label: 'Power Now',
    ),
    NavigationDestination(
      icon: Icon(Icons.energy_savings_leaf_outlined),
      selectedIcon: Icon(Icons.energy_savings_leaf),
      label: 'Stop Waste',
    ),
    NavigationDestination(
      icon: Icon(Icons.nights_stay_outlined),
      selectedIcon: Icon(Icons.nights_stay),
      label: 'Sleep Check',
    ),
    NavigationDestination(
      icon: Icon(Icons.chat_bubble_outline),
      selectedIcon: Icon(Icons.chat_bubble),
      label: 'Ask & Add',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final content = switch (_index) {
      0 => _PowerNow(
        plugs: _plugs,
        hubConnected: _hubConnected,
        estimates: _estimates,
        meterReadings: _meterReadings,
        onHoursChanged: _saveApplianceHours,
        onLoadUsage: _loadApplianceUsage,
        onUsageChanged: _saveApplianceUsage,
      ),
      1 => const _StopWaste(),
      2 => const _SleepCheck(),
      _ => _AskAndAdd(
        api: widget.api,
        credentials: widget.credentials,
        onDevicesChanged: _refreshHub,
      ),
    };
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 74,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF101B2D),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.bolt, color: Color(0xFF26DBBF)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EnergyLens Home',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 3,
                        backgroundColor: Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _hubConnected ? 'HUB CONNECTED' : 'HUB DISCONNECTED',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: _secondary(context),
                                letterSpacing: .7,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('openElectricitySettings'),
            tooltip: 'Electricity settings',
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ElectricitySettingsScreen(
                    api: widget.api,
                    credentials: widget.credentials,
                    onSaved: _refreshHub,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.tune),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Tooltip(
                message: _hubConnected ? 'Hub connected' : 'Hub disconnected',
                child: Semantics(
                  label: _hubConnected ? 'Hub connected' : 'Hub disconnected',
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Icon(
                      _hubConnected
                          ? Icons.check_circle_outline
                          : Icons.power_off_outlined,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (value) {
                setState(() => _index = value);
                _refreshHub();
              },
              labelType: NavigationRailLabelType.all,
              destinations: _destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: SingleChildScrollView(
                  key: ValueKey(_index),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 36),
                  child: content,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) {
                setState(() => _index = value);
                _refreshHub();
              },
              destinations: _destinations,
            ),
    );
  }
}

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _softSurface(BuildContext context) => _isDark(context)
    ? Theme.of(context).colorScheme.surfaceContainerHigh
    : const Color(0xFFF8FAFC);

Color _secondary(BuildContext context) =>
    _isDark(context) ? Theme.of(context).colorScheme.onSurfaceVariant : _muted;

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class _IconWell extends StatelessWidget {
  const _IconWell(this.icon, {this.color = _green});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: _isDark(context) ? .2 : .09),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: color, size: 22),
  );
}

class _Setup extends StatelessWidget {
  const _Setup();

  @override
  Widget build(BuildContext context) => _Surface(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _IconWell(Icons.power_outlined, color: Color(0xFF007FBE)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect a monitored computer',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text(
                'Pair a supported energy-monitoring plug with a local hub. Live readings will appear when the EnergyLens hub connection is available.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: _secondary(context)),
              ),
              const SizedBox(height: 7),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('What you’ll need'),
                children: const [
                  ListTile(
                    leading: Text('1'),
                    title: Text(
                      'A compatible energy-monitoring plug on your computer’s power connection.',
                    ),
                  ),
                  ListTile(
                    leading: Text('2'),
                    title: Text(
                      'A local EnergyLens hub to collect timestamped readings.',
                    ),
                  ),
                  ListTile(
                    leading: Text('3'),
                    title: Text(
                      'Use Ask & Add to find a plug through the hub, or enter its local IP address.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(this.title, this.detail, {this.color = _green});
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      constraints: const BoxConstraints(minHeight: 126),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _softSurface(context),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 4, backgroundColor: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            detail,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: _secondary(context)),
          ),
          const SizedBox(height: 8),
          Text(
            '— unavailable',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _CostMetricTile extends StatelessWidget {
  const _CostMetricTile(
    this.title,
    this.amount,
    this.detail, {
    required this.color,
  });
  final String title;
  final double? amount;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _softSurface(context),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            amount == null
                ? 'Unavailable'
                : '\$${amount!.toStringAsFixed(2)}/month',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          Text(
            detail,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: _secondary(context)),
          ),
        ],
      ),
    ),
  );
}

class _EstimatedCostSummary extends StatelessWidget {
  const _EstimatedCostSummary({required this.plugs, required this.estimates});
  final List<SavedPlug> plugs;
  final Map<int, EnergyEstimate> estimates;

  @override
  Widget build(BuildContext context) {
    final loadCount = plugs
        .where((plug) => plug.connectedAppliance != null)
        .length;
    final values = [
      for (final plug in plugs)
        if (plug.connectedAppliance case final appliance?)
          ?estimates[appliance.id],
    ];
    final measured = values
        .where(
          (item) => item.status == 'measured' && item.estimatedCostUsd != null,
        )
        .toList();
    final sourced = values
        .where(
          (item) => item.status != 'measured' && item.estimatedCostUsd != null,
        )
        .toList();
    final pricedCount = sourced.length;
    final sourcedLoadCount =
        loadCount - values.where((item) => item.status == 'measured').length;
    final loadLabel = sourcedLoadCount == 1 ? 'load' : 'loads';
    final active = sourced.fold<double>(
      0,
      (sum, item) => sum + (item.activeCostUsd ?? 0),
    );
    final standby = sourced.fold<double>(
      0,
      (sum, item) => sum + (item.standbyCostUsd ?? 0),
    );
    final hasStandby = sourced.any((item) => item.standbyCostUsd != null);
    final total = sourced.fold<double>(
      0,
      (sum, item) => sum + (item.estimatedCostUsd ?? 0),
    );
    final measuredTotal = measured.fold<double>(
      0,
      (sum, item) => sum + item.estimatedCostUsd!,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (measured.isNotEmpty) ...[
          _Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OBSERVED LAST 30 DAYS',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _secondary(context),
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${measuredTotal.toStringAsFixed(2)} from ${measured.length} metered ${measured.length == 1 ? 'load' : 'loads'}',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Only sampled intervals are counted. Each device shows its time coverage.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: _secondary(context)),
                ),
              ],
            ),
          ),
          if (sourced.isNotEmpty) const SizedBox(height: 12),
        ],
        if (sourced.isNotEmpty)
          _Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ESTIMATED MONTHLY COST',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _secondary(context),
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${total.toStringAsFixed(2)} from $pricedCount of $sourcedLoadCount $loadLabel',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _CostMetricTile(
                      'Active use',
                      active,
                      'Known active estimates',
                      color: _green,
                    ),
                    const SizedBox(width: 8),
                    _CostMetricTile(
                      'Standby use',
                      hasStandby ? standby : null,
                      'Known standby estimates',
                      color: _rose,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Based on product ratings and entered use. Missing estimates are excluded; this is not a live meter reading.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: _secondary(context)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.aside);
  final String title;
  final String aside;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        aside,
        textAlign: TextAlign.right,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: _secondary(context)),
      ),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
    this.icon,
    this.title,
    this.detail, {
    this.color = const Color(0xFF007FBE),
  });
  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => _Surface(
    child: Row(
      children: [
        _IconWell(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: _secondary(context)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ConnectedLoadRow extends StatefulWidget {
  const _ConnectedLoadRow({
    required this.appliance,
    required this.estimate,
    required this.onHoursChanged,
    required this.onLoadUsage,
    required this.onUsageChanged,
  });

  final SavedAppliance appliance;
  final EnergyEstimate? estimate;
  final Future<void> Function(int, double) onHoursChanged;
  final Future<ApplianceUsageProfile> Function(int) onLoadUsage;
  final Future<ApplianceUsageProfile> Function(int, String, double)
  onUsageChanged;

  @override
  State<_ConnectedLoadRow> createState() => _ConnectedLoadRowState();
}

class _ConnectedLoadRowState extends State<_ConnectedLoadRow> {
  double? _previewHours;
  double? _previewCycles;
  ApplianceUsageProfile? _usageProfile;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    try {
      final profile = await widget.onLoadUsage(widget.appliance.id);
      if (mounted && profile.applianceId == widget.appliance.id) {
        setState(() => _usageProfile = profile);
      }
    } catch (_) {
      // Older hubs have no usage-profile route; keep the existing hours view.
    }
  }

  (double?, double?) _costSplit(double? hours) {
    final estimate = widget.estimate;
    final evidence = estimate?.evidence;
    if (_previewHours == null || hours == null || evidence == null) {
      return (estimate?.activeCostUsd, estimate?.standbyCostUsd);
    }
    final rate = estimate?.rateUsdPerKwh;
    if (rate == null) return (null, null);
    final appliance = widget.appliance;
    if (evidence.datasetId == 'msj5-kqfv') {
      final count = appliance.bulbCount ?? 1;
      final active = evidence.annualKwh * count * hours / 21 / 12 * rate;
      final standby = evidence.standbyWatts == null
          ? null
          : evidence.standbyWatts! * count * (168 - hours) * 52 / 12000 * rate;
      return (active, standby);
    }
    if (evidence.sourceKind == 'user_label' &&
        appliance.combinedInputWatts != null) {
      return (appliance.combinedInputWatts! * hours * 52 / 12000 * rate, null);
    }
    return (estimate?.activeCostUsd, estimate?.standbyCostUsd);
  }

  @override
  void didUpdateWidget(covariant _ConnectedLoadRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.appliance.id != oldWidget.appliance.id) {
      _usageProfile = null;
      _previewCycles = null;
      _loadUsage();
    }
    if (widget.appliance.hoursPerWeek != oldWidget.appliance.hoursPerWeek) {
      _previewHours = null;
      _saveError = null;
    }
  }

  Future<void> _commitCycles(double value) async {
    if (_saving || value == _usageProfile?.value) {
      setState(() => _previewCycles = null);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await widget.onUsageChanged(
        widget.appliance.id,
        'cycles_per_week',
        value,
      );
      if (mounted) {
        setState(() {
          _usageProfile = saved;
          _previewCycles = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewCycles = null;
          _saveError = 'Could not save cycles. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _commitHours(double value) async {
    if (_saving || value == widget.appliance.hoursPerWeek) {
      setState(() => _previewHours = null);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onHoursChanged(widget.appliance.id, value);
      if (mounted) setState(() => _previewHours = null);
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewHours = null;
          _saveError = 'Could not save hours. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _commitProfileHours(double value) async {
    if (_saving || value == _usageProfile?.value) {
      setState(() => _previewHours = null);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await widget.onUsageChanged(
        widget.appliance.id,
        'hours_per_week',
        value,
      );
      if (mounted) {
        setState(() {
          _usageProfile = saved;
          _previewHours = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewHours = null;
          _saveError = 'Could not save hours. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appliance = widget.appliance;
    final estimate = widget.estimate;
    final evidence = estimate?.evidence;
    final measured = estimate?.status == 'measured';
    final hours = _previewHours ?? appliance.hoursPerWeek;
    final initialHours = appliance.initialHoursPerWeek;
    final showProfileHours =
        _usageProfile?.usageKind == 'hours_per_week' &&
        !measured &&
        (evidence?.sourceKind == 'category_typical' ||
            evidence?.usageBasis.startsWith('hours_per_day:') == true) &&
        !(appliance.category == 'lighting' &&
            appliance.loadKind == 'replaceable_bulb');
    final (activeCost, standbyCost) = _costSplit(hours);
    final cost = _previewHours == null
        ? estimate?.estimatedCostUsd
        : activeCost == null
        ? null
        : activeCost + (standbyCost ?? 0);
    final rateLabel = estimate?.rateSourceLabel;
    final sourceLabel = measured
        ? 'Meter readings · ${((estimate?.measurementCoverageFraction ?? 0) * 100).round()}% of the last 30 days covered'
        : evidence == null
        ? 'Energy source unavailable'
        : energySourceHeading(evidence);
    final onTimeOnly =
        standbyCost == null &&
        (evidence?.sourceKind == 'user_label' ||
            evidence?.datasetId == 'msj5-kqfv');
    final costHeading = measured
        ? 'Observed last 30 days'
        : evidence?.sourceKind == 'energy_star_archive'
        ? 'Historical test-profile cost'
        : evidence?.sourceKind == 'oem_family'
        ? 'Manufacturer family test-profile cost'
        : onTimeOnly
        ? 'Estimated on-time'
        : standbyCost != null
        ? 'Estimated total'
        : 'Estimated monthly cost';
    return _Surface(
      child: Row(
        children: [
          const _IconWell(Icons.lightbulb_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appliance.name,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  cost != null
                      ? measured
                            ? '$costHeading: \$${cost.toStringAsFixed(2)}'
                            : '$costHeading: \$${cost.toStringAsFixed(2)}/month'
                      : estimate?.estimatedKwh != null
                      ? 'Add your ZIP code or bill rate for cost'
                      : 'Estimate unavailable',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cost == null ? _secondary(context) : _green,
                    fontWeight: cost == null
                        ? FontWeight.normal
                        : FontWeight.w700,
                  ),
                ),
                if (activeCost != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${evidence?.sourceKind == 'category_typical' ? 'Active use' : 'On-time use'}: \$${activeCost.toStringAsFixed(2)}/month',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: _secondary(context)),
                  ),
                  Text(
                    standbyCost == null
                        ? 'Standby use: unavailable'
                        : 'Standby use: \$${standbyCost.toStringAsFixed(2)}/month',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: _secondary(context)),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      evidence?.sourceKind == 'energy_star'
                          ? Icons.verified_outlined
                          : Icons.info_outline,
                      size: 16,
                      color: _secondary(context),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        sourceLabel,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: _secondary(context)),
                      ),
                    ),
                  ],
                ),
                if (cost != null && rateLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Rate: $rateLabel',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: _secondary(context)),
                  ),
                ],
                if (appliance.category == 'lighting' &&
                    appliance.loadKind == 'replaceable_bulb' &&
                    (evidence?.datasetId == 'msj5-kqfv' ||
                        evidence?.sourceKind == 'user_label') &&
                    hours != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'On time: ${hours.toStringAsFixed(0)} hours/week',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: _secondary(context)),
                  ),
                  Slider(
                    key: Key('appliance-hours-${appliance.id}'),
                    value: hours.clamp(0, 168),
                    min: 0,
                    max: 168,
                    divisions: 168,
                    label: '${hours.toStringAsFixed(0)} hours/week',
                    semanticFormatterCallback: (value) =>
                        '${value.toStringAsFixed(0)} hours per week',
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _previewHours = value;
                            _saveError = null;
                          }),
                    onChangeEnd: _saving ? null : _commitHours,
                  ),
                  if (initialHours != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: Key('reset-appliance-hours-${appliance.id}'),
                        onPressed: _saving || hours == initialHours
                            ? null
                            : () => _commitHours(initialHours),
                        icon: const Icon(Icons.restore),
                        label: Text(
                          'Reset to ${initialHours.toStringAsFixed(0)} hours/week',
                        ),
                      ),
                    ),
                  if (_saving) const LinearProgressIndicator(),
                  if (_saveError != null)
                    Text(
                      _saveError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
                if (showProfileHours) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Use: ${(_previewHours ?? _usageProfile!.value).toStringAsFixed(0)} hours/week',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: _secondary(context)),
                  ),
                  Slider(
                    key: Key('appliance-profile-hours-${appliance.id}'),
                    value: (_previewHours ?? _usageProfile!.value).clamp(
                      _usageProfile!.min,
                      _usageProfile!.max,
                    ),
                    min: _usageProfile!.min,
                    max: _usageProfile!.max,
                    divisions:
                        ((_usageProfile!.max - _usageProfile!.min) /
                                _usageProfile!.step)
                            .round(),
                    label:
                        '${(_previewHours ?? _usageProfile!.value).toStringAsFixed(0)} hours/week',
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _previewHours = value;
                            _saveError = null;
                          }),
                    onChangeEnd: _saving ? null : _commitProfileHours,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: Key('reset-appliance-profile-hours-${appliance.id}'),
                      onPressed:
                          _saving ||
                              _usageProfile!.value ==
                                  _usageProfile!.initialValue
                          ? null
                          : () => _commitProfileHours(
                              _usageProfile!.initialValue,
                            ),
                      icon: const Icon(Icons.restore),
                      label: Text(
                        'Reset to ${_usageProfile!.initialValue.toStringAsFixed(0)} hours/week',
                      ),
                    ),
                  ),
                  if (_saving) const LinearProgressIndicator(),
                  if (_saveError != null)
                    Text(
                      _saveError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
                if (_usageProfile?.usageKind == 'cycles_per_week' &&
                    !measured &&
                    (evidence?.sourceKind == 'category_typical' ||
                        evidence?.usageBasis.startsWith('cycles_per_year:') ==
                            true)) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Use: ${(_previewCycles ?? _usageProfile!.value).toStringAsFixed(1)} cycles/week',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: _secondary(context)),
                  ),
                  Slider(
                    key: Key('appliance-cycles-${appliance.id}'),
                    value: (_previewCycles ?? _usageProfile!.value).clamp(
                      _usageProfile!.min,
                      _usageProfile!.max,
                    ),
                    min: _usageProfile!.min,
                    max: _usageProfile!.max,
                    divisions:
                        ((_usageProfile!.max - _usageProfile!.min) /
                                _usageProfile!.step)
                            .round(),
                    label:
                        '${(_previewCycles ?? _usageProfile!.value).toStringAsFixed(1)} cycles/week',
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _previewCycles = value;
                            _saveError = null;
                          }),
                    onChangeEnd: _saving ? null : _commitCycles,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: Key('reset-appliance-cycles-${appliance.id}'),
                      onPressed:
                          _saving ||
                              _usageProfile!.value ==
                                  _usageProfile!.initialValue
                          ? null
                          : () => _commitCycles(_usageProfile!.initialValue),
                      icon: const Icon(Icons.restore),
                      label: Text(
                        'Reset to ${_usageProfile!.initialValue.toStringAsFixed(1)} cycles/week',
                      ),
                    ),
                  ),
                  if (_saving) const LinearProgressIndicator(),
                  if (_saveError != null)
                    Text(
                      _saveError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PowerNow extends StatefulWidget {
  const _PowerNow({
    required this.plugs,
    required this.hubConnected,
    required this.estimates,
    required this.meterReadings,
    required this.onHoursChanged,
    required this.onLoadUsage,
    required this.onUsageChanged,
  });

  final List<SavedPlug> plugs;
  final bool hubConnected;
  final Map<int, EnergyEstimate> estimates;
  final Map<String, DeviceEnergy> meterReadings;
  final Future<void> Function(int, double) onHoursChanged;
  final Future<ApplianceUsageProfile> Function(int) onLoadUsage;
  final Future<ApplianceUsageProfile> Function(int, String, double)
  onUsageChanged;

  @override
  State<_PowerNow> createState() => _PowerNowState();
}

class _PowerNowState extends State<_PowerNow> {
  final Set<String> _collapsedPlugIds = {};

  List<Widget> _savedDevices() => [
    _SectionTitle(
      'Where Your Power Is Going',
      widget.plugs.isEmpty
          ? 'Saved devices'
          : '${widget.plugs.length} saved plug${widget.plugs.length == 1 ? '' : 's'}',
    ),
    const SizedBox(height: 10),
    if (widget.plugs.isEmpty)
      _InfoRow(
        Icons.power_outlined,
        widget.hubConnected
            ? 'No smart plugs saved on this hub'
            : 'Hub connection needed',
        widget.hubConnected
            ? 'Use Ask & Add to discover and save a plug.'
            : 'Use Ask & Add to connect your EnergyLens hub.',
      )
    else
      for (final plug in widget.plugs) ...[
        Builder(
          builder: (context) {
            final appliance = plug.connectedAppliance;
            final expanded =
                appliance != null && !_collapsedPlugIds.contains(plug.id);
            final meter = widget.meterReadings[plug.id];
            final meterDetail = plug.meterStatus == 'absent'
                ? 'No energy meter · ${plug.room.isEmpty ? 'Room not set' : plug.room}'
                : meter?.latestWatts != null
                ? 'Recent meter reading · ${meter!.latestWatts!.toStringAsFixed(1)} W${meter.latestSample == null ? '' : ' · ${_sampleTime(meter.latestSample!.ts)}'}'
                : meter?.status == 'measured'
                ? 'Meter history available · no current reading'
                : 'Waiting for a meter reading';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Surface(
                  child: Semantics(
                    key: Key('plug-expand-${plug.id}'),
                    button: appliance != null,
                    expanded: expanded,
                    label: '${plug.name}, ${plug.model}. $meterDetail',
                    hint: appliance == null
                        ? null
                        : expanded
                        ? 'Hide connected appliance ${appliance.name}'
                        : 'Show connected appliance ${appliance.name}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: appliance == null
                          ? null
                          : () => setState(() {
                              if (expanded) {
                                _collapsedPlugIds.add(plug.id);
                              } else {
                                _collapsedPlugIds.remove(plug.id);
                              }
                            }),
                      child: Row(
                        children: [
                          _IconWell(Icons.power_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${plug.name} · ${plug.model}',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  meterDetail,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: _secondary(context)),
                                ),
                                if (meter?.status == 'measured') ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    '${meter!.totalKwh.toStringAsFixed(3)} kWh measured in the last 24 hours · ${(meter.coverageFraction * 100).round()}% time coverage',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: _secondary(context)),
                                  ),
                                  if (meter.observedCostUsd
                                      case final cost?) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      '\$${cost.toStringAsFixed(2)} observed cost during covered time · ${meter.rateSourceLabel ?? 'Electricity rate'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: _secondary(context),
                                          ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                          if (appliance != null) ...[
                            const SizedBox(width: 8),
                            Icon(
                              expanded ? Icons.expand_less : Icons.expand_more,
                              semanticLabel: expanded
                                  ? 'Hide connected appliance'
                                  : 'Show connected appliance',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (appliance != null && expanded) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Row(
                      children: [
                        Container(
                          width: 2,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ConnectedLoadRow(
                            appliance: appliance,
                            estimate: widget.estimates[appliance.id],
                            onHoursChanged: widget.onHoursChanged,
                            onLoadUsage: widget.onLoadUsage,
                            onUsageChanged: widget.onUsageChanged,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 8),
      ],
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Surface(
        child: Row(
          children: [
            const _IconWell(Icons.energy_savings_leaf_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your home energy, at a glance',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    widget.plugs.isEmpty
                        ? 'Connect a device to see how your electricity is being used.'
                        : '${widget.plugs.length} smart plug${widget.plugs.length == 1 ? '' : 's'} saved on your hub.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: _secondary(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      ..._savedDevices(),
      const SizedBox(height: 18),
      if (widget.estimates.values.any(
        (value) => value.estimatedCostUsd != null,
      ))
        _EstimatedCostSummary(plugs: widget.plugs, estimates: widget.estimates)
      else if (widget.meterReadings.values.any(
            (value) => value.status == 'measured',
          ) ||
          widget.estimates.values.any((value) => value.status == 'measured'))
        const _InfoRow(
          Icons.bolt_outlined,
          'Meter readings received',
          'Measured energy is shown above. Add a ZIP code or bill rate to see cost.',
        )
      else
        _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CURRENT PACE',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: _secondary(context),
                                letterSpacing: 1,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Right Now in Your Home',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.12,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 9),
                  const _IconWell(
                    Icons.bolt_outlined,
                    color: Color(0xFF193D5A),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: _softSurface(context),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Text(
                      '—',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: _green,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'every hour',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: _secondary(context)),
                      ),
                    ),
                    Text(
                      '— Watts',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: _secondary(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: _softSurface(context),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MetricTile(
                    'Useful Power',
                    'Activity and device context will show useful work.',
                  ),
                  SizedBox(width: 8),
                  _MetricTile(
                    'Wasted Power',
                    'Waste requires measured evidence from your home.',
                    color: _rose,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Waiting for a live reading from a connected device.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: _secondary(context)),
              ),
            ],
          ),
        ),
      const SizedBox(height: 18),
      const _InfoRow(
        Icons.help_outline,
        'What can EnergyLens show?',
        'Measured draw, device activity, and cost will appear after hub setup.',
      ),
      const SizedBox(height: 18),
      const _Setup(),
    ],
  );
}

class _StopWaste extends StatelessWidget {
  const _StopWaste();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                border: Border.all(color: const Color(0xFFFECBD4)),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'MONITORING NOT CONNECTED',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFC2414C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Find What’s Wasting Electricity',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.12),
            ),
            const SizedBox(height: 5),
            Text(
              'EnergyLens needs measured readings and device context before it can identify avoidable use.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: _secondary(context)),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _softSurface(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_outlined, size: 18, color: _muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Findings and verified savings will appear after monitoring starts.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: _secondary(context)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const _InfoRow(
        Icons.energy_savings_leaf_outlined,
        'No findings yet',
        'When a device shows avoidable draw, its evidence and next step will appear here.',
        color: _green,
      ),
      const SizedBox(height: 18),
      const _Setup(),
      const SizedBox(height: 18),
      const _InfoRow(
        Icons.verified_outlined,
        'Verified wins will live here',
        'Compare observed use before and after an action to see the result.',
        color: _green,
      ),
    ],
  );
}

class _SleepMetric extends StatelessWidget {
  const _SleepMetric(this.title, this.detail, {this.color});
  final String title;
  final String detail;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      constraints: const BoxConstraints(minHeight: 95),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color == null
            ? _softSurface(context)
            : color!.withValues(alpha: .05),
        border: Border.all(
          color: color == null
              ? Theme.of(context).colorScheme.outlineVariant
              : color!.withValues(alpha: .18),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color ?? _secondary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '—',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          Text(
            detail,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: _secondary(context)),
          ),
        ],
      ),
    ),
  );
}

class _SleepCheck extends StatelessWidget {
  const _SleepCheck();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.nights_stay_outlined,
                  color: Color(0xFF008BC1),
                  size: 28,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Last Night’s Summary',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _softSurface(context),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'No night tracked',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: _secondary(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _softSurface(context),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFCBD9DF),
                        width: 5,
                      ),
                    ),
                    child: Text(
                      '—',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sleep score unavailable',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _green,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Connect a monitored device to understand its overnight draw.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _secondary(context)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Row(
              children: [
                _SleepMetric('Total spent', 'No readings'),
                SizedBox(width: 7),
                _SleepMetric('Necessary', 'Not classified'),
                SizedBox(width: 7),
                _SleepMetric('Keepable', 'Not measured', color: _rose),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const _InfoRow(
        Icons.nights_stay_outlined,
        'Night Sleep Mode',
        'Automatic overnight controls will appear when device control is available.',
        color: _green,
      ),
      const SizedBox(height: 24),
      const _SectionTitle('What Ran Overnight', 'No devices yet'),
      const SizedBox(height: 10),
      const _InfoRow(
        Icons.schedule_outlined,
        'Nothing to review yet',
        'Connect a monitored device to begin collecting overnight history.',
      ),
      const SizedBox(height: 18),
      const _Setup(),
    ],
  );
}

enum _AskMode { ask, connect }

class _AskAndAdd extends StatefulWidget {
  const _AskAndAdd({
    required this.api,
    required this.credentials,
    required this.onDevicesChanged,
  });

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;
  final VoidCallback onDevicesChanged;

  @override
  State<_AskAndAdd> createState() => _AskAndAddState();
}

class _AskAndAddState extends State<_AskAndAdd> {
  _AskMode mode = _AskMode.ask;
  List<SavedAppliance> _manualDevices = const [];
  String? _deleteError;
  int? _deletingId;

  Future<void> _loadManualDevices() async {
    try {
      final (address, token) = await widget.credentials.read();
      if (address == null || token == null) return;
      final devices = await widget.api.appliances(address, token);
      if (mounted) {
        setState(
          () => _manualDevices = devices
              .where((device) => device.onboardingMethod == 'manual')
              .toList(),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _deleteError = 'Could not load saved devices from the hub.',
        );
      }
    }
  }

  Future<void> _deleteManualDevice(SavedAppliance device) async {
    if (_deletingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete device?'),
        content: Text(
          'Delete “${device.name}” from this hub? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deletingId = device.id;
      _deleteError = null;
    });
    try {
      final (address, token) = await widget.credentials.read();
      if (address == null || token == null) {
        throw StateError('Hub connection needed');
      }
      await widget.api.deleteManualAppliance(address, token, device.id);
      if (!mounted) return;
      setState(
        () => _manualDevices = _manualDevices
            .where((item) => item.id != device.id)
            .toList(),
      );
      widget.onDevicesChanged();
      await _loadManualDevices();
    } catch (error) {
      if (mounted) {
        setState(
          () => _deleteError = error is StateError
              ? error.message
              : 'Could not delete the device. Check the hub connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 2),
      SegmentedButton<_AskMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: _AskMode.ask,
            icon: Icon(Icons.chat_bubble_outline),
            label: Text('Ask Your Home'),
          ),
          ButtonSegment(
            value: _AskMode.connect,
            icon: Icon(Icons.add_circle_outline),
            label: Text('Connect Appliance'),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (selection) {
          setState(() => mode = selection.first);
          if (mode == _AskMode.connect) _loadManualDevices();
        },
      ),
      const SizedBox(height: 20),
      if (mode == _AskMode.ask) ...[
        _Surface(
          child: Row(
            children: [
              const _IconWell(Icons.chat_bubble_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask your home',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Questions about power and your electric bill will work when measured data is available.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: _secondary(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Surface(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _IconWell(Icons.bolt_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ENERGYLENS ASSISTANT',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _green,
                        letterSpacing: .7,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Answers need your home’s data',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The assistant is not connected yet. Connect a monitored device to make answers specific to your home.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: _secondary(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _InfoRow(
          Icons.help_outline,
          'Questions become available after connection',
          'Measured readings will make answers specific to your home.',
        ),
      ] else ...[
        _Surface(
          child: Row(
            children: [
              const _IconWell(Icons.power_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect an appliance',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Find a supported plug through your local hub. Kasa HS103 has no energy meter; choose a metering model for measured power.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: _secondary(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DiscoveryScreen()),
            );
            if (!mounted) return;
            _loadManualDevices();
            widget.onDevicesChanged();
          },
          icon: const Icon(Icons.radar),
          label: const Text('Find a smart plug'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const ApplianceOnboardingScreen(method: 'manual'),
              ),
            );
            if (!mounted) return;
            _loadManualDevices();
            widget.onDevicesChanged();
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Enter device details'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const ApplianceOnboardingScreen(method: 'photo'),
              ),
            );
            if (!mounted) return;
            _loadManualDevices();
            widget.onDevicesChanged();
          },
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Identify from a photo'),
        ),
        if (_manualDevices.isNotEmpty || _deleteError != null) ...[
          const SizedBox(height: 18),
          Text(
            'Manually added devices',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_deleteError != null)
            Text(
              _deleteError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final device in _manualDevices)
            Card(
              child: ListTile(
                title: Text(device.name),
                subtitle: Text(
                  device.room.isEmpty
                      ? device.category
                      : '${device.room} · ${device.category}',
                ),
                trailing: IconButton(
                  key: Key('ask-delete-appliance-${device.id}'),
                  tooltip: 'Delete ${device.name}',
                  onPressed: _deletingId == null
                      ? () => _deleteManualDevice(device)
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
        ],
      ],
      const SizedBox(height: 18),
      const _Setup(),
    ],
  );
}
