import 'package:flutter/material.dart';

import '../../auth/api_client.dart';
import '../../auth/auth_service.dart';
import 'auth_scaffold.dart';

/// Confirms the address with the emailed code, then signs in.
///
/// Takes the password when it has one — coming straight from sign-up — so the
/// user isn't made to type it again the moment they verify. Arriving here from
/// a blocked sign-in, it has the password too.
class VerifyEmailScreen extends StatefulWidget {
  final AuthService auth;
  final String email;
  final String? password;
  final VoidCallback onVerified;

  const VerifyEmailScreen({
    super.key,
    required this.auth,
    required this.email,
    required this.onVerified,
    this.password,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      await widget.auth.verifyEmail(
        email: widget.email,
        code: _code.text.trim(),
      );

      final password = widget.password;
      if (password != null) {
        await widget.auth.signIn(email: widget.email, password: password);
        if (mounted) widget.onVerified();
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pop();
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

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.auth.resendVerification(widget.email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = 'Sent. The newest code is the only one that works.';
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
      icon: Icons.mark_email_read_outlined,
      title: 'Confirm your email',
      subtitle: 'We sent a 6-digit code to ${widget.email}.',
      actionLabel: 'Confirm',
      busy: _busy,
      onAction: _submit,

      footer: Center(
        child: AppTextActionWrapper(
          busy: _busy,
          onPressed: _resend,
        ),
      ),
      children: [
        if (_error != null) AuthMessage(message: _error!),
        if (_notice != null) AuthMessage(message: _notice!, isError: false),
        AuthField(
          controller: _code,
          label: 'Confirmation code',
          hint: '123456',
          icon: Icons.pin_outlined,
          keyboardType: TextInputType.number,
          autofocus: true,
          autofillHints: const [AutofillHints.oneTimeCode],
          validator: AuthValidators.code,
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}

/// Small indirection so the footer can disable itself while busy.
class AppTextActionWrapper extends StatelessWidget {
  final bool busy;
  final VoidCallback onPressed;

  const AppTextActionWrapper({
    super.key,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: busy ? null : onPressed,
      icon: const Icon(Icons.refresh_rounded, size: 16),
      label: const Text('Send a new code'),
    );
  }
}
