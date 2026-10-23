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
    this.linkOrigin = '',
    this.usernameMode = false,
    this.onUsernameRegistered,
    this.onEmailRegister,
    this.initialEmail = '',
    this.onEmailChanged,
    this.isCurrent,
  });

  final CloudRegistrationService service;
  final String linkOrigin;
  final bool usernameMode;
  final Future<void> Function(String username, String password)?
  onUsernameRegistered;
  final Future<void> Function(String email, String password)? onEmailRegister;
  final String initialEmail;
  final ValueChanged<String>? onEmailChanged;
  final bool Function()? isCurrent;

  @override
  State<CloudRegistrationScreen> createState() =>
      _CloudRegistrationScreenState();
}

class _CloudRegistrationScreenState extends State<CloudRegistrationScreen> {
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _remoteAttempted = false;
  bool _showPassword = false;
  bool _showConfirm = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _password.clear();
    _confirm.clear();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_busy || (_remoteAttempted && !widget.usernameMode)) return;
    final email = widget.usernameMode
        ? _email.text.replaceAll(RegExp(r'^ +| +$'), '').toLowerCase()
        : _email.text.trim().toLowerCase();
    final password = _password.text;
    final passwordBytes = utf8.encode(password);
    final validIdentifier = widget.usernameMode
        ? RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$').hasMatch(email)
        : email.length <= 254 &&
              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    if (!validIdentifier ||
        (widget.usernameMode
            ? passwordBytes.length < 12
            : password.runes.length < 12) ||
        passwordBytes.length > 1024 ||
        password.codeUnits.contains(0) ||
        password != _confirm.text) {
      setState(
        () =>
            _error = widget.usernameMode ? 'Check your username and password.' : 'Enter a valid email and matching password of at least 12 characters.',
      );
      _password.clear();
      _confirm.clear();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.usernameMode) {
        await widget.service.requestRegistration(email, password);
      } else {
        _remoteAttempted = true;
        final register = widget.onEmailRegister;
        if (register == null) throw StateError('Missing registration handoff');
        await register(email, password);
      }
      if (!mounted ||
          (widget.usernameMode && widget.isCurrent?.call() == false)) {
        return;
      }
      _password.clear();
      _confirm.clear();
      if (widget.usernameMode && widget.onUsernameRegistered != null) {
        try {
          await widget.onUsernameRegistered!(email, password);
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
        if (!widget.usernameMode &&
            (error.statusCode == 400 || error.statusCode == 422)) {
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
                        key: const Key('registrationEmail'),
                        controller: _email,
                        onChanged: widget.onEmailChanged,
                        enabled: !_busy,
                        autofillHints: widget.usernameMode
                            ? const [AutofillHints.username]
                            : const [AutofillHints.email],
                        keyboardType: widget.usernameMode
                            ? TextInputType.text
                            : TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: widget.usernameMode
                              ? 'Username'
                              : 'Email ID',
                        ),
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
                  onPressed: _busy || (_remoteAttempted && !widget.usernameMode)
                      ? null
                      : _register,
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
