import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_tariff.dart';
import '../../core/cloud_api/cloud_home.dart';

class CloudElectricityRateScreen extends StatefulWidget {
  const CloudElectricityRateScreen({
    super.key,
    required this.api,
    required this.home,
    this.gas = false,
  });

  final CloudApiClient api;
  final CloudHome home;
  final bool gas;

  @override
  State<CloudElectricityRateScreen> createState() =>
      _CloudElectricityRateScreenState();
}

class CloudGasRateScreen extends CloudElectricityRateScreen {
  const CloudGasRateScreen({super.key, required super.api, required super.home})
    : super(gas: true);
}

class _CloudElectricityRateScreenState
    extends State<CloudElectricityRateScreen> {
  final _rate = TextEditingController();
  final _sourceDate = TextEditingController();
  final _effectiveDate = TextEditingController();
  CloudTariff? _current;
  String? _error;
  String? _message;
  bool _loading = true;
  bool _saving = false;
  String? _pendingKey;
  Map<String, dynamic>? _pendingBody;

  String get _fuelLabel => widget.gas ? 'natural gas' : 'electricity';
  String get _unit => widget.gas ? 'therm' : 'kWh';
  String get _title => widget.gas ? 'Cloud gas rate' : 'Cloud electricity rate';

  @override
  void initState() {
    super.initState();
    for (final field in [_rate, _sourceDate, _effectiveDate]) {
      field.addListener(() {
        _pendingKey = null;
        _pendingBody = null;
      });
    }
    _load();
  }

  @override
  void dispose() {
    _rate.dispose();
    _sourceDate.dispose();
    _effectiveDate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _current = null;
    });
    try {
      final tariffs = widget.gas
          ? await widget.api.gasTariffs(widget.home.id)
          : await widget.api.electricityTariffs(widget.home.id);
      if (mounted) {
        setState(() => _current = tariffs.isEmpty ? null : tariffs.single);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load this home’s $_title. Retry.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime? _date(String text) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
    final date = DateTime.tryParse('${text}T00:00:00Z');
    return date?.toIso8601String().startsWith(text) == true ? date : null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final rate = _rate.text.trim();
    final source = _date(_sourceDate.text.trim());
    final effective = _date(_effectiveDate.text.trim());
    final now = DateTime.now().toUtc();
    if (!RegExp(r'^(0|[1-9][0-9]{0,9})(\.[0-9]{1,8})?$').hasMatch(rate) ||
        source == null ||
        effective == null ||
        source.isAfter(now) ||
        source.isBefore(now.subtract(const Duration(days: 540))) ||
        effective.isAfter(now)) {
      setState(
        () => _error =
            'Enter a nonnegative USD/$_unit rate, a recent bill date, and the date this rate began (YYYY-MM-DD).',
      );
      return;
    }
    _pendingKey ??= newCloudIdempotencyKey();
    _pendingBody ??= {
      'fuel': widget.gas ? 'natural_gas' : 'electricity',
      'rate': rate,
      'rate_unit': _unit,
      'currency': 'USD',
      'rate_kind': 'user_tariff',
      'source_ref': 'Customer-entered $_fuelLabel bill',
      'source_as_of': source.toIso8601String(),
      'is_fallback': false,
      'fixed_charge': null,
      'effective_from': effective.toIso8601String(),
      'effective_to': null,
    };
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final saved = widget.gas
          ? await widget.api.createGasTariff(
              widget.home.id,
              _pendingBody!,
              idempotencyKey: _pendingKey!,
            )
          : await widget.api.createElectricityTariff(
              widget.home.id,
              _pendingBody!,
              idempotencyKey: _pendingKey!,
            );
      if (!mounted) return;
      setState(() {
        _current = saved;
        _pendingKey = null;
        _pendingBody = null;
        _message = '$_title saved for ${widget.home.name}.';
      });
    } on CloudApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.statusCode == 409
              ? 'Rate request conflicted. Refresh this home’s rate before trying again.'
              : 'Could not confirm the Cloud rate. Retry unchanged details or refresh.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm the Cloud rate. Retry unchanged details or refresh.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_title)),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.home.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                widget.gas
                    ? 'Enter the marginal natural gas rate from a recent bill in USD per therm for this Cloud home. Exclude fixed charges. A rate alone does not establish gas consumption, Useful cost, Waste, your actual bill, or savings.'
                    : 'Save a rate from a recent electricity bill for this Cloud home. It is separate from local hub settings. Fixed charges are excluded; this rate does not establish your actual bill or savings.',
              ),
              const SizedBox(height: 12),
              if (_loading) const LinearProgressIndicator(),
              if (_current case final current?)
                Text(
                  'Current Cloud rate: ${current.rate} USD/$_unit · bill dated ${current.sourceAsOf.toUtc().toIso8601String().substring(0, 10)} · effective from ${current.effectiveFrom.toUtc().toIso8601String().substring(0, 10)}',
                ),
              if (!_loading && _current == null)
                Text('No current $_title is available.'),
              TextButton(
                onPressed: _saving ? null : _load,
                child: const Text('Refresh rate'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('cloudRate'),
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      '${widget.gas ? 'Gas' : 'Electricity'} rate (USD/$_unit)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('cloudRateSourceDate'),
                controller: _sourceDate,
                decoration: const InputDecoration(
                  labelText: 'Bill date (YYYY-MM-DD)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('cloudRateEffectiveDate'),
                controller: _effectiveDate,
                decoration: const InputDecoration(
                  labelText: 'Rate began (YYYY-MM-DD)',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use the start date shown on the bill. A monthly estimate needs a rate covering its full month.',
              ),
              if (_error != null)
                Text(_error!, key: const Key('cloudRateError')),
              if (_message != null)
                Text(_message!, key: const Key('cloudRateMessage')),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving || _loading ? null : _save,
                child: Text('Save $_title'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
