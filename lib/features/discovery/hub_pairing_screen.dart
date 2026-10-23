import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'discovery_api.dart';
import 'discovery_credentials.dart';
import '../../core/backend_error.dart';

/// Imports the operator's one-time local enrollment details.
class HubPairingScreen extends StatefulWidget {
  const HubPairingScreen({
    super.key,
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
    this.onSetUpLater,
  });

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;
  final VoidCallback? onSetUpLater;

  @override
  State<HubPairingScreen> createState() => _HubPairingScreenState();
}

class _HubPairingScreenState extends State<HubPairingScreen> {
  final _operatorJson = TextEditingController();
  final _address = TextEditingController();
  final _hubId = TextEditingController();
  final _secret = TextEditingController();
  bool _busy = false;
  bool _pairingFailed = false;
  String? _error;

  Future<void> _scanQr() async {
    final value = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _PairingQrScreen()));
    if (value != null && mounted) {
      _operatorJson.text = value;
    }
  }

  Future<void> _pair() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _pairingFailed = false;
    });
    try {
      final PairingDetails details;
      if (_operatorJson.text.trim().isNotEmpty) {
        final decoded = jsonDecode(_operatorJson.text.trim());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Paste the operator JSON object.');
        }
        details = PairingDetails.fromJson(decoded);
      } else {
        details = PairingDetails.fromManualFields(
          address: _address.text,
          hubId: _hubId.text,
          enrollmentSecret: _secret.text,
        );
      }
      final random = Random.secure();
      final clientId =
          'energylens-mobile-${List<int>.generate(16, (_) => random.nextInt(256)).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
      _pairingFailed = true;
      await widget.credentials.claimAndStore(
        details,
        clientId: clientId,
        api: widget.api,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error) {
            FormatException(:final message) => message,
            PairingException(:final message) => message,
            _ => internalErrorMessage,
          };
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _operatorJson.dispose();
    _address.dispose();
    _hubId.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pair with your hub')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Use the one-time details displayed by your local hub. The app checks its HTTPS certificate and hub ID before sending the enrollment secret.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('operatorPairingJson'),
            controller: _operatorJson,
            decoration: const InputDecoration(
              labelText: 'Paste hub pairing JSON',
              helperText: 'Includes address, hub ID, and enrollment secret',
              border: OutlineInputBorder(),
            ),
            minLines: 3,
            maxLines: 7,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _scanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan hub QR code'),
          ),
          const SizedBox(height: 16),
          const Text('Or enter the details manually'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pairingAddress'),
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'Hub HTTPS address and SHA-256 pin',
              hintText: 'https://192.168.1.20:18787#sha256=…',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pairingHubId'),
            controller: _hubId,
            decoration: const InputDecoration(
              labelText: 'Hub ID',
              border: OutlineInputBorder(),
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pairingSecret'),
            controller: _secret,
            decoration: const InputDecoration(
              labelText: 'One-time enrollment secret',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            autocorrect: false,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _pair,
            child: Text(_busy ? 'Verifying hub…' : 'Verify and pair'),
          ),
          if (_pairingFailed &&
              _error != null &&
              widget.onSetUpLater != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : widget.onSetUpLater,
              child: const Text('Set up later'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _PairingQrScreen extends StatefulWidget {
  const _PairingQrScreen();

  @override
  State<_PairingQrScreen> createState() => _PairingQrScreenState();
}

class _PairingQrScreenState extends State<_PairingQrScreen> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan hub QR code')),
    body: SafeArea(
      child: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_accepted) return;
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null && value.isNotEmpty) {
                  _accepted = true;
                  Navigator.of(context).pop(value);
                  return;
                }
              }
            },
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Point the camera at the pairing QR code shown by your hub.',
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
