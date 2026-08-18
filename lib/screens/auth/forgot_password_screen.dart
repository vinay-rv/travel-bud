import 'package:flutter/material.dart';

import '../../auth/api_client.dart';
import '../../auth/auth_service.dart';
import '../../widgets/ui.dart';
import 'auth_scaffold.dart';

/// Requests a reset code, then takes the new password.
///
/// Both steps live on one screen because they are one errand, and because
/// bouncing between screens loses the code someone just read off their phone.
class ForgotPasswordScreen extends StatefulWidget {
  final AuthService auth;

  const ForgotPasswordScreen({super.key, required this.auth});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _codeSent = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (AuthValidators.email(_email.text) != null) {
      _formKey.currentState!.validate();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      await widget.auth.forgotPassword(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _codeSent = true;
        // Says "if" on purpose: the API gives the same answer for unknown
        // addresses, so this must not imply the account exists.
        _notice = 'If that address has an account, a code is on its way.';
      });
    } on ApiUnavailable {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Cannot reach Packmate. Check your connection and try again.';
      });
    }
  }

  Future<void> _reset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      await widget.auth.resetPassword(
        email: _email.text.trim(),
        code: _code.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed. Sign in with your new one.'),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on ApiUnavailable {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Cannot reach Packmate. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      formKey: _formKey,
      icon: Icons.lock_reset_rounded,
      title: 'Reset your password',
      subtitle: _codeSent
          ? 'Enter the code we emailed you, and choose a new password.'
          : 'We will email you a code to set a new password.',
      actionLabel: _codeSent ? 'Set new password' : 'Send code',
      busy: _busy,
      onAction: _codeSent ? _reset : _sendCode,
      children: [
        if (_error != null) AuthMessage(message: _error!),
        if (_notice != null) AuthMessage(message: _notice!, isError: false),
        AuthField(
          controller: _email,
          label: 'Email',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          validator: AuthValidators.email,
        ),
        if (_codeSent) ...[
          AuthField(
            controller: _code,
            label: 'Reset code',
            hint: '123456',
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            validator: AuthValidators.code,
          ),
          AuthField(
            controller: _password,
            label: 'New password',
            hint: 'At least 10 characters',
            icon: Icons.lock_outline_rounded,
            obscure: true,
            autofillHints: const [AutofillHints.newPassword],
            validator: AuthValidators.password,
            onSubmitted: (_) => _reset(),
          ),
          const FormHint(
            'Changing your password signs you out everywhere else, which is '
            'the point if someone else had it.',
          ),
        ],
      ],
    );
  }
}
