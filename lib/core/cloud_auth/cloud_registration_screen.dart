import 'dart:convert';

import 'package:flutter/material.dart';

import 'cloud_local_auth.dart';
import '../backend_error.dart';
import 'cloud_auth.dart';

/// The first-party Cloud adapter supplies this only when local auth is enabled.
class CloudRegistrationScreen extends StatefulWidget {
  const CloudRegistrationScreen({
    super.key,
    required this.service,
    this.onUsernameRegistered,
    this.isCurrent,
  });

  final CloudRegistrationService service;
  final Future<void> Function(String username, String password)?
  onUsernameRegistered;
  final bool Function()? isCurrent;

  @override
  State<CloudRegistrationScreen> createState() =>
      _CloudRegistrationScreenState();
}

class _CloudRegistrationScreenState extends State<CloudRegistrationScreen> {
  final _userId = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _remoteAttempted = false;
  bool _showPassword = false;
  bool _showConfirm = false;
  String? _error;

  @override
  void dispose() {
    _password.clear();
    _confirm.clear();
    _userId.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_busy || _remoteAttempted) return;
    final userId = _userId.text.trim().toLowerCase();
    final password = _password.text;
    final passwordBytes = utf8.encode(password);
    final validIdentifier = RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$')
        .hasMatch(userId);
    if (!validIdentifier ||
        password.runes.length < 8 ||
        passwordBytes.length > 1024 ||
        password.codeUnits.contains(0) ||
        password != _confirm.text) {
      setState(() => _error = 'Check your username and password.');
      _password.clear();
      _confirm.clear();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _remoteAttempted = true;
      await widget.service.requestRegistration(userId, password);
      if (!mounted || widget.isCurrent?.call() == false) {
        return;
      }
      _password.clear();
      _confirm.clear();
      if (widget.onUsernameRegistered != null) {
        try {
          await widget.onUsernameRegistered!(userId, password);
          if (mounted) Navigator.of(context).pop();
          return;
        } catch (_) {
          if (mounted) {
            setState(
              () => _error =
                  'Account created. Sign in with your username to continue.',
            );
          }
          return;
        }
      }
      if (mounted) Navigator.of(context).pop();
    } on CloudLocalAuthException catch (error) {
      if (mounted) {
        if (error.statusCode == 400 || error.statusCode == 422) {
          _remoteAttempted = false;
        }
        setState(
          () => _error = isInputRejectionStatus(error.statusCode)
              ? 'Could not submit the request. Try again.'
              : internalErrorMessage,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = internalErrorMessage);
      }
    } finally {
      if (mounted) {
        _password.clear();
        _confirm.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create account')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ...[
                AutofillGroup(
                  child: Column(
                    children: [
                      TextField(
                        key: const Key('registrationUserId'),
                        controller: _userId,
                        enabled: !_busy,
                        autofillHints: const [AutofillHints.username],
                        keyboardType: TextInputType.text,
                        decoration: const InputDecoration(labelText: 'User ID'),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('registrationPassword'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: !_showPassword,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('registrationConfirm'),
                        controller: _confirm,
                        enabled: !_busy,
                        obscureText: !_showConfirm,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _register(),
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          suffixIcon: IconButton(
                            tooltip: _showConfirm
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: () =>
                                setState(() => _showConfirm = !_showConfirm),
                            icon: Icon(
                              _showConfirm
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || _remoteAttempted ? null : _register,
                  child: const Text('Create account'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, key: const Key('registrationError')),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
