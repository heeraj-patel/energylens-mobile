import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend_error.dart';
import 'cloud_auth.dart';
import 'cloud_auth_link.dart';
import 'cloud_local_auth.dart';
import 'cloud_recovery_diagnostics.dart';

class CloudRecoveryScreen extends StatefulWidget {
  const CloudRecoveryScreen({
    super.key,
    required this.service,
    this.usernameMode = false,
    this.linkOrigin = '',
    this.initialEmail = '',
    this.onEmailChanged,
    this.onResetSuccess,
    this.diagnosticSink,
  });

  final LocalCloudAuthService service;
  final bool usernameMode;
  final String linkOrigin;
  final String initialEmail;
  final ValueChanged<String>? onEmailChanged;
  final Future<void> Function(String email, String password)? onResetSuccess;
  final void Function(String event)? diagnosticSink;

  @override
  State<CloudRecoveryScreen> createState() => _CloudRecoveryScreenState();
}

class _CloudRecoveryScreenState extends State<CloudRecoveryScreen> {
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _errorVisibilityKey = GlobalKey();
  String? _capturedToken;
  bool _busy = false;
  bool _requested = false;
  bool _showReset = false;
  bool _completed = false;
  bool _showPassword = false;
  bool _showConfirm = false;
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

  void _showError(String message) {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _error = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final errorContext = _errorVisibilityKey.currentContext;
      if (!mounted || errorContext == null) return;
      Scrollable.ensureVisible(
        errorContext,
        duration: const Duration(milliseconds: 200),
        alignment: 0.6,
      );
    });
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
    if (_busy) {
      recordCloudRecoveryEvent(
        'reset_duplicate_ignored',
        sink: widget.diagnosticSink,
      );
      return;
    }
    final token = _capturedToken;
    final password = _password.text;
    final identity = _email.text.trim().toLowerCase();
    if (widget.usernameMode &&
        !RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$').hasMatch(identity)) {
      recordCloudRecoveryEvent(
        'reset_validation_user_id',
        sink: widget.diagnosticSink,
      );
      _showError('Could not reset the password. Try again later.');
      _password.clear();
      _confirm.clear();
      return;
    }
    if (!widget.usernameMode && token == null) {
      recordCloudRecoveryEvent(
        'reset_validation_token',
        sink: widget.diagnosticSink,
      );
      _showError('Paste the reset link from your email.');
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
      recordCloudRecoveryEvent(
        'reset_validation_password',
        sink: widget.diagnosticSink,
      );
      _showError('Enter a matching new password of at least 12 characters.');
      _capturedToken = null;
      _password.clear();
      _confirm.clear();
      return;
    }
    _capturedToken = null;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    var postSucceeded = false;
    try {
      recordCloudRecoveryEvent('reset_post_start', sink: widget.diagnosticSink);
      if (widget.usernameMode) {
        await widget.service.resetUsernamePassword(identity, password);
      } else {
        await widget.service.resetPassword(token!, password);
      }
      postSucceeded = true;
      recordCloudRecoveryEvent('reset_post_204', sink: widget.diagnosticSink);
      if (!mounted) return;
      if (widget.onResetSuccess != null) {
        recordCloudRecoveryEvent(
          'reset_handoff_start',
          sink: widget.diagnosticSink,
        );
        await widget.onResetSuccess!(identity, password);
        recordCloudRecoveryEvent(
          'reset_handoff_returned',
          sink: widget.diagnosticSink,
        );
      } else {
        setState(() => _completed = true);
      }
    } on CloudLocalAuthException catch (error) {
      recordCloudRecoveryEvent(
        '${postSucceeded ? 'reset_handoff' : 'reset_post'}_http_${error.statusCode}',
        sink: widget.diagnosticSink,
      );
      _showError(
        !widget.usernameMode && error.statusCode == 401
            ? 'This reset link has expired or was already used. Request a new link.'
            : isInputRejectionStatus(error.statusCode)
            ? 'Could not reset the password. Try again later.'
            : internalErrorMessage,
      );
    } on TimeoutException {
      recordCloudRecoveryEvent(
        postSucceeded ? 'reset_handoff_timeout' : 'reset_post_timeout',
        sink: widget.diagnosticSink,
      );
      _showError(internalErrorMessage);
    } catch (_) {
      recordCloudRecoveryEvent(
        postSucceeded ? 'reset_handoff_failure' : 'reset_post_failure',
        sink: widget.diagnosticSink,
      );
      _showError(internalErrorMessage);
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
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'New password (at least 12 characters)',
                      suffixIcon: IconButton(
                        tooltip: _showPassword
                            ? 'Hide password'
                            : 'Show password',
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                  ),
                  TextField(
                    key: const Key('resetConfirm'),
                    controller: _confirm,
                    enabled: !_busy,
                    obscureText: !_showConfirm,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_busy &&
                          (widget.usernameMode || _capturedToken != null)) {
                        _reset();
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Confirm new password',
                      suffixIcon: IconButton(
                        tooltip: _showConfirm
                            ? 'Hide password'
                            : 'Show password',
                        onPressed: _busy
                            ? null
                            : () =>
                                  setState(() => _showConfirm = !_showConfirm),
                        icon: Icon(
                          _showConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    Semantics(
                      key: _errorVisibilityKey,
                      liveRegion: true,
                      child: Text(_error!, key: const Key('recoveryError')),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(
                    key: const Key('submitPasswordReset'),
                    onPressed:
                        _busy ||
                            (!widget.usernameMode && _capturedToken == null)
                        ? null
                        : _reset,
                    child: _busy
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Reset password'),
                            ],
                          )
                        : const Text('Reset password'),
                  ),
                ],
              ] else
                const Text(
                  'Password updated. Return to sign in with your new password.',
                  key: Key('recoveryCompleted'),
                ),
              if (_error != null && (!_showReset || _completed)) ...[
                const SizedBox(height: 12),
                Semantics(
                  key: _errorVisibilityKey,
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
