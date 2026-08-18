import 'package:flutter/material.dart';

import '../../auth/api_client.dart';
import '../../auth/auth_service.dart';
import '../../widgets/ui.dart';
import 'auth_scaffold.dart';
import 'verify_email_screen.dart';

class SignUpScreen extends StatefulWidget {
  final AuthService auth;
  final VoidCallback onSignedIn;

  const SignUpScreen({super.key, required this.auth, required this.onSignedIn});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        displayName: _name.text,
      );
      if (!mounted) return;
      // Signing up does not sign you in: the address has to be confirmed first.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VerifyEmailScreen(
            auth: widget.auth,
            email: _email.text.trim(),
            password: _password.text,
            onVerified: widget.onSignedIn,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.code == 'email_taken'
            ? 'That email already has an account. Try signing in instead.'
            : e.message;
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
      icon: Icons.person_add_alt_rounded,
      title: 'Create your account',
      subtitle:
          'Your trips sync across your devices and survive a new phone.',
      actionLabel: 'Create account',
      busy: _busy,
      onAction: _submit,
      children: [
        if (_error != null) AuthMessage(message: _error!),
        AuthField(
          controller: _name,
          label: 'Your name (optional)',
          icon: Icons.badge_outlined,
          autofillHints: const [AutofillHints.name],
        ),
        AuthField(
          controller: _email,
          label: 'Email',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          validator: AuthValidators.email,
        ),
        AuthField(
          controller: _password,
          label: 'Password',
          hint: 'At least 10 characters',
          icon: Icons.lock_outline_rounded,
          obscure: true,
          autofillHints: const [AutofillHints.newPassword],
          validator: AuthValidators.password,
          onSubmitted: (_) => _submit(),
        ),
        const FormHint(
          'A long phrase you will remember beats a short complicated one. '
          'We will email you a code to confirm the address.',
        ),
      ],
    );
  }
}
