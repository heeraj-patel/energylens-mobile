import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart' show newCloudIdempotencyKey;
import '../../core/cloud_api/cloud_preferences.dart' show CloudVersioned;
import '../../core/backend_error.dart';

enum AccountProfileField { owner, email, password }

/// Native credential form; passwords never enter the packaged Settings DOM.
class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({
    super.key,
    required this.api,
    required this.field,
    required this.isCurrentAccount,
  });

  const AccountProfileScreen.localPilotPassword({
    super.key,
    required this.isCurrentAccount,
  }) : api = null,
       field = AccountProfileField.password;

  final CloudApiClient? api;
  final AccountProfileField field;
  final bool Function() isCurrentAccount;

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  CloudVersioned<CloudAccount>? _account;
  bool _loading = true;
  bool _saving = false;
  bool _failed = false;
  bool _backendFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.api == null) {
      _loading = false;
      return;
    }
    try {
      final account = await widget.api!.accountProfile();
      if (!mounted || !widget.isCurrentAccount()) return;
      setState(() {
        _account = account;
        _name.text = account.value.displayName ?? '';
        _loading = false;
      });
    } catch (_) {
      if (mounted && widget.isCurrentAccount()) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _loading ||
        !widget.isCurrentAccount() ||
        (widget.api != null && _account == null)) {
      return;
    }
    final name = _name.text.trim();
    final email = _email.text.trim().toLowerCase();
    final invalid = switch (widget.field) {
      AccountProfileField.owner => name.isEmpty,
      AccountProfileField.email =>
        email.isEmpty || _currentPassword.text.isEmpty,
      AccountProfileField.password =>
        _currentPassword.text.isEmpty ||
            _newPassword.text.length < 12 ||
            _newPassword.text != _confirmPassword.text,
    };
    if (invalid) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _saving = true;
      _failed = false;
      _backendFailed = false;
    });
    try {
      if (widget.api == null) {
        // Owner-approved pilot-only simulation; no credentials or API writes.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (mounted && widget.isCurrentAccount()) {
          Navigator.of(context).pop(true);
        }
        return;
      }
      switch (widget.field) {
        case AccountProfileField.owner:
          await widget.api!.updateAccountOwner(
            name,
            ifMatch: _account!.etag,
            idempotencyKey: newCloudIdempotencyKey(),
          );
        case AccountProfileField.email:
          await widget.api!.changeLocalEmail(
            email,
            _currentPassword.text,
            ifMatch: _account!.etag,
            idempotencyKey: newCloudIdempotencyKey(),
          );
        case AccountProfileField.password:
          await widget.api!.changeLocalPassword(
            _currentPassword.text,
            _newPassword.text,
          );
      }
      if (mounted && widget.isCurrentAccount()) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted && widget.isCurrentAccount()) {
        final rejected =
            error is CloudApiException &&
            isInputRejectionStatus(error.statusCode);
        setState(() {
          _failed = rejected;
          _backendFailed = !rejected;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.field) {
      AccountProfileField.owner => 'Edit account owner',
      AccountProfileField.email => 'Change email',
      AccountProfileField.password => 'Change password',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (widget.field == AccountProfileField.owner)
              TextField(
                controller: _name,
                maxLength: 120,
                enabled: !_loading && !_saving,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
            if (widget.field == AccountProfileField.email)
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enabled: !_loading && !_saving,
                decoration: const InputDecoration(labelText: 'New email'),
              ),
            if (widget.field != AccountProfileField.owner)
              TextField(
                controller: _currentPassword,
                obscureText: true,
                enabled: !_loading && !_saving,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
            if (widget.field == AccountProfileField.password) ...[
              TextField(
                controller: _newPassword,
                obscureText: true,
                enabled: !_loading && !_saving,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              TextField(
                controller: _confirmPassword,
                obscureText: true,
                enabled: !_loading && !_saving,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
              ),
            ],
            if (_failed)
              const Text(
                'Couldn’t save changes. Check the fields and try again.',
              ),
            if (_backendFailed) const Text(internalErrorMessage),
            const SizedBox(height: 24),
            FilledButton(
              onPressed:
                  _loading ||
                      _saving ||
                      (widget.api != null && _account == null)
                  ? null
                  : _save,
              child: const Text('Save changes'),
            ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
