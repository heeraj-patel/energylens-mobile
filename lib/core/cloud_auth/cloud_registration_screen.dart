import 'dart:convert';

import 'package:flutter/material.dart';

import 'cloud_local_auth.dart';
import 'cloud_auth.dart';

/// The first-party Cloud adapter supplies this only when local auth is enabled.
class CloudRegistrationScreen extends StatefulWidget {
  const CloudRegistrationScreen({super.key, required this.service});

  final CloudRegistrationService service;

  @override
  State<CloudRegistrationScreen> createState() =>
      _CloudRegistrationScreenState();
}

class _CloudRegistrationScreenState extends State<CloudRegistrationScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _token = TextEditingController();
  bool _busy = false;
  bool _accepted = false;
  bool _verificationSubmitted = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;
    final passwordBytes = utf8.encode(password);
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        password.runes.length < 12 ||
        passwordBytes.length > 1024 ||
        password.contains('\u0000') ||
        password != _confirm.text) {
      setState(
        () => _error = 'Enter a valid email and matching password of at least 12 characters.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.requestRegistration(email, password);
      _password.clear();
      _confirm.clear();
      if (mounted) setState(() => _accepted = true);
    } on CloudLocalAuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.statusCode == 404
              ? 'Account creation is not available on this Cloud server.'
              : 'Could not submit the request. Try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not submit the request. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    final token = _token.text.trim();
    if (token.isEmpty || token.length > 4096) {
      setState(() => _error = 'Enter the verification token from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.verifyEmail(token);
      _token.clear();
      if (mounted) setState(() => _verificationSubmitted = true);
    } on CloudLocalAuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.statusCode == 404
              ? 'Email verification is not available on this Cloud server.'
              : 'Could not verify this token. Check the email and try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not verify this token. Check the email and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
                const Text(
                  'Enter an email and password to request an EnergyLens account. If the request can proceed, check your email for verification instructions.',
                ),
                const SizedBox(height: 16),
                AutofillGroup(
                  child: Column(
                    children: [
                      TextField(
                        key: const Key('registrationEmail'),
                        controller: _email,
                        enabled: !_busy,
                        autofillHints: const [AutofillHints.email],
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
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
                  child: const Text('Request account'),
                ),
              ] else ...[
                const Text(
                  'If this email can be registered, verification instructions will arrive there. The request does not sign you in.',
                  key: Key('registrationAccepted'),
                ),
                const SizedBox(height: 16),
                if (!_verificationSubmitted) ...[
                  TextField(
                    key: const Key('registrationToken'),
                    controller: _token,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Verification token from email',
                    ),
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
