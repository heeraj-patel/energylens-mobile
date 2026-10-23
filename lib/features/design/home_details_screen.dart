import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart';
import 'settings_mutation_adapter.dart';
import '../../core/backend_error.dart';

/// Native home edit. The WebView never receives credentials or write tokens.
class HomeDetailsScreen extends StatefulWidget {
  const HomeDetailsScreen({
    super.key,
    required this.api,
    required this.homeId,
    required this.isCurrentHome,
  });

  final CloudApiClient api;
  final String homeId;
  final bool Function() isCurrentHome;

  @override
  State<HomeDetailsScreen> createState() => _HomeDetailsScreenState();
}

class _HomeDetailsScreenState extends State<HomeDetailsScreen> {
  late final SettingsMutationAdapter _settings = SettingsMutationAdapter(
    CloudSettingsMutationSource(widget.api),
  );
  final _name = TextEditingController();
  final _postal = TextEditingController();
  final _country = TextEditingController();
  final _gasRate = TextEditingController();
  String _gasRateKey = newCloudIdempotencyKey();
  String? _gasRateAt;
  bool _loading = true;
  bool _saving = false;
  bool _conflict = false;
  bool _backendFailed = false;
  bool _timezoneUnresolved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await _settings.load(widget.homeId);
      if (!mounted || !widget.isCurrentHome() || snapshot == null) return;
      setState(() {
        _name.text = snapshot.home.name;
        _postal.text = snapshot.home.postalCode;
        _country.text = snapshot.home.countryCode;
        _loading = false;
      });
    } catch (_) {
      if (mounted && widget.isCurrentHome()) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final before = _settings.snapshot;
    if (before == null || _saving || !widget.isCurrentHome()) return;
    final valid = CloudHomeCreate.validate(
      name: _name.text,
      timezone: before.home.timezone,
      countryCode: _country.text,
      postalCode: _postal.text,
    );
    if (valid == null || !_gasRateValid) return;
    setState(() {
      _saving = true;
      _conflict = false;
      _backendFailed = false;
      _timezoneUnresolved = false;
    });
    try {
      final locationChanged =
          valid.countryCode != before.home.countryCode ||
          valid.postalCode != before.home.postalCode;
      if (valid.name != before.home.name || locationChanged) {
        final after = await _settings.updateHome(
          CloudHomePatch(
            name: valid.name == before.home.name ? null : valid.name,
            countryCode: locationChanged ? valid.countryCode : null,
            postalCode: locationChanged ? valid.postalCode : null,
          ),
          idempotencyKey: newCloudIdempotencyKey(),
        );
        if (!mounted || !widget.isCurrentHome() || after == null) return;
      }
      if (!_hasPropane && _gasRate.text.trim().isNotEmpty) {
        await _saveGasRate();
        if (!mounted || !widget.isCurrentHome()) return;
        _gasRate.clear();
        _gasRateKey = newCloudIdempotencyKey();
        _gasRateAt = null;
      }
      if (locationChanged &&
          _settings.lastHomeTimezoneResolution == 'unresolved') {
        setState(() => _timezoneUnresolved = true);
        return;
      }
      Navigator.of(context).pop(true);
    } on CloudApiException catch (error) {
      if (!mounted || !widget.isCurrentHome()) return;
      if (error.statusCode == 409 || error.statusCode == 412) {
        setState(() => _conflict = true);
        await _load();
      } else {
        setState(() => _backendFailed = true);
      }
    } catch (_) {
      if (mounted && widget.isCurrentHome()) {
        setState(() => _backendFailed = true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static final _gasRatePattern = RegExp(
    r'^(0|[1-9][0-9]{0,9})(\.[0-9]{1,8})?$',
  );

  bool get _gasRateValid {
    final text = _gasRate.text.trim();
    if (text.isEmpty) return true;
    return _gasRatePattern.hasMatch(text) && _gasRateInRange(text);
  }

  static bool _gasRateInRange(String text) {
    final rate = double.parse(text);
    return rate >= 0.20 && rate <= 10.00;
  }

  bool get _gasRateOutOfRange {
    final text = _gasRate.text.trim();
    return _gasRatePattern.hasMatch(text) && !_gasRateInRange(text);
  }

  /// Propane cost is not supported yet, so a propane home gets no gas rate.
  bool get _hasPropane =>
      _settings.snapshot?.appliances?.any((a) => a.fuel == 'propane') ?? false;

  /// A user gas tariff effective now, in USD per therm. The timestamp stays
  /// fixed with the idempotency key so a retry sends the identical body.
  Future<void> _saveGasRate() {
    final now = _gasRateAt ??= DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
    return widget.api.createGasTariff(widget.homeId, {
      'fuel': 'natural_gas',
      'rate': _gasRate.text.trim(),
      'rate_unit': 'therm',
      'currency': 'USD',
      'rate_kind': 'user_tariff',
      'source_ref': 'energylens-mobile:settings',
      'source_as_of': now,
      'is_fallback': false,
      'fixed_charge': null,
      'effective_from': now,
      'effective_to': null,
    }, idempotencyKey: _gasRateKey);
  }

  @override
  void dispose() {
    _gasRate.dispose();
    _settings.clear();
    _name.dispose();
    _postal.dispose();
    _country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Home details')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_loading) const LinearProgressIndicator(),
          TextField(
            controller: _name,
            maxLength: 120,
            enabled: !_loading && !_saving,
            decoration: const InputDecoration(labelText: 'Home name'),
          ),
          TextField(
            controller: _postal,
            maxLength: 20,
            enabled: !_loading && !_saving,
            onChanged: (_) => setState(() => _timezoneUnresolved = false),
            decoration: const InputDecoration(labelText: 'ZIP code'),
          ),
          if (!_loading &&
              _settings.snapshot != null &&
              _postal.text.trim().toUpperCase() !=
                  _settings.snapshot!.home.postalCode)
            const Text(
              'Future energy calculations will use this ZIP code and its time zone. Existing demo dates and amounts will stay the same.',
            ),
          TextField(
            controller: _country,
            maxLength: 2,
            enabled: !_loading && !_saving,
            decoration: const InputDecoration(labelText: 'Country'),
          ),
          if (!_hasPropane)
            TextField(
              controller: _gasRate,
              enabled: !_loading && !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {
                _gasRateKey = newCloudIdempotencyKey();
                _gasRateAt = null;
              }),
              decoration: InputDecoration(
                labelText: 'Gas rate (\$/therm)',
                errorText: _gasRateOutOfRange
                    ? 'Enter a gas rate between \$0.20 and \$10.00 per therm.'
                    : null,
              ),
            ),
          if (_conflict)
            const Text('Home details changed elsewhere. Reload and try again.'),
          if (_backendFailed) const Text(internalErrorMessage),
          if (_timezoneUnresolved)
            const Text(
              'ZIP code saved. We couldn’t determine its time zone, so your home time zone stayed the same.',
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed:
                _loading ||
                    _saving ||
                    _settings.snapshot == null ||
                    !_gasRateValid
                ? null
                : _save,
            child: const Text('Save changes'),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}
