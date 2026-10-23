import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend_error.dart';
import 'cloud_auth.dart';
import 'cloud_auth_link.dart';
import 'cloud_local_auth.dart';

class CloudRecoveryScreen extends StatefulWidget {
  const CloudRecoveryScreen({
    super.key,
    required this.service,
    this.usernameMode = false,
    this.linkOrigin = '',
    this.initialEmail = '',
    this.onEmailChanged,
    this.onResetSuccess,
  });

  final LocalCloudAuthService service;
  final bool usernameMode;
  final String linkOrigin;
  final String initialEmail;
  final ValueChanged<String>? onEmailChanged;
  final Future<void> Function(String email, String password)? onResetSuccess;

  @override
  State<CloudRecoveryScreen> createState() => _CloudRecoveryScreenState();
}

class _CloudRecoveryScreenState extends State<CloudRecoveryScreen> {
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _capturedToken;
  bool _busy = false;
  bool _requested = false;
  bool _showReset = false;
  bool _completed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
    _showReset = widget.usernameMode;
  }

  @override
  void dispose() {
    _password.clear();
    _confirm.clear();
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
          () => _error = isInputRejectionStatus(error.statusCode)
              ? 'Could not submit the request. Try again later.'
              : internalErrorMessage,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = internalErrorMessage);
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
    final password = _password.text;
    final identity = _email.text.trim().toLowerCase();
    if (widget.usernameMode &&
        !RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$').hasMatch(identity)) {
      setState(() => _error = 'Could not reset the password. Try again later.');
      _password.clear();
      _confirm.clear();
      return;
    }
    if (!widget.usernameMode && token == null) {
      setState(() => _error = 'Paste the reset link from your email.');
      _password.clear();
      _confirm.clear();
      return;
    }
    if ((widget.usernameMode
            ? utf8.encode(password).length < 12
            : password.runes.length < 12) ||
        utf8.encode(password).length > 1024 ||
        password.codeUnits.contains(0) ||
        password != _confirm.text) {
      setState(
        () =>
            _error = 'Enter a matching new password of at least 12 characters.',
      );
      _capturedToken = null;
      _password.clear();
      _confirm.clear();
      return;
    }
    _capturedToken = null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.usernameMode) {
        await widget.service.resetUsernamePassword(identity, password);
      } else {
        await widget.service.resetPassword(token!, password);
      }
      if (!mounted) return;
      if (widget.onResetSuccess != null) {
        await widget.onResetSuccess!(identity, password);
      } else {
        setState(() => _completed = true);
      }
    } on CloudLocalAuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = !widget.usernameMode && error.statusCode == 401
              ? 'This reset link has expired or was already used. Request a new link.'
              : isInputRejectionStatus(error.statusCode)
              ? 'Could not reset the password. Try again later.'
              : internalErrorMessage,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = internalErrorMessage);
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
                if (!widget.usernameMode) ...[
                  const Text(
                    'Enter your email to request a one-hour reset link.',
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: Key(
                    widget.usernameMode ? 'recoveryUserId' : 'recoveryEmail',
                  ),
                  controller: _email,
                  onChanged: widget.onEmailChanged,
                  enabled: !_busy,
                  keyboardType: widget.usernameMode
                      ? TextInputType.text
                      : TextInputType.emailAddress,
                  autofillHints: widget.usernameMode
                      ? const [AutofillHints.username]
                      : const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: widget.usernameMode ? 'User ID' : 'Email ID',
                  ),
                ),
                if (!widget.usernameMode) ...[
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
                ],
                if (_showReset) ...[
                  const Divider(),
                  if (!widget.usernameMode) ...[
                    const Text(
                      'Copy the reset link from your email, then paste it here. The link expires after one hour and can be used once.',
                    ),
                    OutlinedButton(
                      key: const Key('pasteResetLink'),
                      onPressed: _busy ? null : _captureToken,
                      child: const Text('Paste reset link or token'),
                    ),
                    if (_capturedToken != null) const Text('Reset link ready.'),
                  ],
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
                    onPressed:
                        _busy ||
                            (!widget.usernameMode && _capturedToken == null)
                        ? null
                        : _reset,
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
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, key: const Key('recoveryError')),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
