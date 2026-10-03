import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cloud_auth.dart';
import 'cloud_auth_link.dart';
import 'cloud_local_auth.dart';

class CloudRecoveryScreen extends StatefulWidget {
  const CloudRecoveryScreen({
    super.key,
    required this.service,
    this.linkOrigin = '',
  });

  final LocalCloudAuthService service;
  final String linkOrigin;

  @override
  State<CloudRecoveryScreen> createState() => _CloudRecoveryScreenState();
}

class _CloudRecoveryScreenState extends State<CloudRecoveryScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _capturedToken;
  bool _busy = false;
  bool _requested = false;
  bool _showReset = false;
  bool _completed = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _capturedToken = null;
    super.dispose();
  }

  Future<void> _request() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.requestRecovery(email);
      if (mounted) {
        setState(() {
          _requested = true;
          _showReset = true;
        });
      }
    } on CloudLocalAuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.statusCode == 404
              ? 'Password recovery is not available on this Cloud server.'
              : 'Could not submit the request. Try again later.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not submit the request. Try again later.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _captureToken() async {
    try {
      final copied = (await Clipboard.getData('text/plain'))?.text;
      final token = CloudAuthLink.capture(
        copied ?? '',
        path: '/reset-password',
        trustedOrigin: widget.linkOrigin,
      );
      if (copied != null) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
      if (!mounted) return;
      setState(() {
        _capturedToken = token;
        _error = token == null
            ? 'Copy the reset link or token from your email and try again.'
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not paste the link. Copy it and try again.',
        );
      }
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    final token = _capturedToken;
    _capturedToken = null;
    final password = _password.text;
    if (token == null) {
      setState(() => _error = 'Paste the reset link from your email.');
      return;
    }
    if (password.runes.length < 12 ||
        utf8.encode(password).length > 1024 ||
        password.codeUnits.contains(0) ||
        password != _confirm.text) {
      setState(
        () =>
            _error = 'Enter a matching new password of at least 12 characters.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.resetPassword(token, password);
      if (mounted) setState(() => _completed = true);
    } on CloudLocalAuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.statusCode == 404
              ? 'Password reset is not available on this Cloud server.'
              : error.statusCode == 401
              ? 'This link is invalid, expired, or already used. Request a new one.'
              : 'Could not reset the password. Try again later.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not reset the password. Try again later.',
        );
      }
    } finally {
      _password.clear();
      _confirm.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reset password')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!_completed) ...[
                const Text(
                  'Enter your email to request a one-hour reset link.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('recoveryEmail'),
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _request,
                  child: const Text('Request reset link'),
                ),
                if (_requested)
                  const Text(
                    'If this email can receive a reset link, it will arrive there. This does not sign you in.',
                    key: Key('recoveryAccepted'),
                  ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _showReset = true),
                  child: const Text('I have a reset link'),
                ),
                if (_showReset) ...[
                  const Divider(),
                  const Text(
                    'Copy the reset link from your email, then paste it here. The link expires after one hour and can be used once.',
                  ),
                  OutlinedButton(
                    key: const Key('pasteResetLink'),
                    onPressed: _busy ? null : _captureToken,
                    child: const Text('Paste reset link or token'),
                  ),
                  if (_capturedToken != null) const Text('Reset link ready.'),
                  TextField(
                    key: const Key('resetPassword'),
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'New password (at least 12 characters)',
                    ),
                  ),
                  TextField(
                    key: const Key('resetConfirm'),
                    controller: _confirm,
                    enabled: !_busy,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('submitPasswordReset'),
                    onPressed: _busy ? null : _reset,
                    child: const Text('Reset password'),
                  ),
                ],
              ] else
                const Text(
                  'Password updated. Return to sign in with your new password.',
                  key: Key('recoveryCompleted'),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, key: const Key('recoveryError')),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
