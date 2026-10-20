import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cloud_local_auth.dart';
import '../backend_error.dart';
import 'cloud_auth.dart';
import 'cloud_auth_link.dart';

/// The first-party Cloud adapter supplies this only when local auth is enabled.
class CloudRegistrationScreen extends StatefulWidget {
  const CloudRegistrationScreen({
    super.key,
    required this.service,
    this.linkOrigin = '',
    this.usernameMode = false,
    this.onUsernameRegistered,
    this.isCurrent,
  });

  final CloudRegistrationService service;
  final String linkOrigin;
  final bool usernameMode;
  final Future<void> Function(String username, String password)?
  onUsernameRegistered;
  final bool Function()? isCurrent;

  @override
  State<CloudRegistrationScreen> createState() =>
      _CloudRegistrationScreenState();
}

class _CloudRegistrationScreenState extends State<CloudRegistrationScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _capturedToken;
  bool _busy = false;
  bool _accepted = false;
  bool _verificationSubmitted = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _capturedToken = null;
    super.dispose();
  }

  Future<void> _register() async {
    if (_busy) return;
    final email = widget.usernameMode
        ? _email.text.replaceAll(RegExp(r'^ +| +$'), '').toLowerCase()
        : _email.text.trim();
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
      await widget.service.requestRegistration(email, password);
      if (!mounted || widget.isCurrent?.call() == false) return;
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
      if (mounted) setState(() => _accepted = true);
    } on CloudLocalAuthException catch (error) {
      if (mounted) {
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

  Future<void> _verify() async {
    if (_busy) return;
    final token = _capturedToken;
    _capturedToken = null;
    if (token == null) {
      setState(() => _error = 'Paste the verification link from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.verifyEmail(token);
      if (mounted) setState(() => _verificationSubmitted = true);
    } on CloudLocalAuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = isInputRejectionStatus(error.statusCode) ||
                  error.statusCode == 401
              ? 'Could not verify this token. Check the email and try again.'
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

  Future<void> _captureToken() async {
    try {
      final copied = (await Clipboard.getData('text/plain'))?.text;
      final token = CloudAuthLink.capture(
        copied ?? '',
        path: '/verify-email',
        trustedOrigin: widget.linkOrigin,
      );
      if (copied != null) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
      if (!mounted) return;
      setState(() {
        _capturedToken = token;
        _error = token == null
            ? 'Copy the verification link or token from your email and try again.'
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
              if (!_accepted) ...[
                Text(
                  widget.usernameMode
                      ? 'Choose a username and password to create your EnergyLens account.'
                      : 'Enter an email and password to request an EnergyLens account. If the request can proceed, check your email for verification instructions.',
                ),
                const SizedBox(height: 16),
                AutofillGroup(
                  child: Column(
                    children: [
                      TextField(
                        key: const Key('registrationEmail'),
                        controller: _email,
                        enabled: !_busy,
                        autofillHints: widget.usernameMode
                            ? const [AutofillHints.username]
                            : const [AutofillHints.email],
                        keyboardType: widget.usernameMode
                            ? TextInputType.text
                            : TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: widget.usernameMode ? 'Username' : 'Email',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('registrationPassword'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          labelText: 'Password (at least 12 characters)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('registrationConfirm'),
                        controller: _confirm,
                        enabled: !_busy,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _register,
                  child: Text(
                    widget.usernameMode ? 'Create account' : 'Request account',
                  ),
                ),
              ] else ...[
                const Text(
                  'If this email can be registered, verification instructions will arrive there. The request does not sign you in.',
                  key: Key('registrationAccepted'),
                ),
                const SizedBox(height: 16),
                if (!_verificationSubmitted) ...[
                  OutlinedButton(
                    key: const Key('pasteVerificationLink'),
                    onPressed: _busy ? null : _captureToken,
                    child: const Text('Paste verification link or token'),
                  ),
                  if (_capturedToken != null)
                    const Text(
                      'Verification link ready. Links expire after one hour.',
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: const Text('Verify email'),
                  ),
                ] else
                  const Text(
                    'Verification request completed. Return to sign in when your email is confirmed.',
                    key: Key('registrationVerificationSubmitted'),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, key: const Key('registrationError')),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
