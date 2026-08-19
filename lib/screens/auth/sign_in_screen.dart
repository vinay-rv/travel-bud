import 'package:flutter/material.dart';

import '../../auth/api_client.dart';
import '../../auth/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'auth_scaffold.dart';
import 'forgot_password_screen.dart';
import 'sign_up_screen.dart';
import 'verify_email_screen.dart';

/// The way in. Also the app's first screen for anyone without a session.
class SignInScreen extends StatefulWidget {
  final AuthService auth;

  /// Called once a session exists, so the gate can rebuild.
  final VoidCallback onSignedIn;

  const SignInScreen({super.key, required this.auth, required this.onSignedIn});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
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
      await widget.auth.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (mounted) widget.onSignedIn();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Signing up and then never confirming is common enough to deserve a way
      // forward rather than a dead end.
      if (e.code == 'email_not_verified') {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VerifyEmailScreen(
              auth: widget.auth,
              email: _email.text.trim(),
              password: _password.text,
              onVerified: widget.onSignedIn,
            ),
          ),
        );
        if (mounted) setState(() => _busy = false);
        return;
      }
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
        } catch (error) {
      // Anything unforeseen — a missing platform plugin, a malformed response.
      // Whatever it is, the button must stop spinning and say something, or the
      // screen simply hangs with no way forward.
      debugPrint('Sign-in failed: $error');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      formKey: _formKey,
      showBack: false,
      icon: Icons.explore_rounded,
      title: 'Welcome back',
      subtitle: 'Sign in to reach your trips on any device.',
      actionLabel: 'Sign in',
      busy: _busy,
      onAction: _submit,

      // Wraps rather than a Row: "New here?" plus the action does not fit on
      // one line on a 360dp phone, or at a large text scale.
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'New here?',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: AppSpacing.sm),
          AppTextAction(
            label: 'Create an account',
            icon: Icons.person_add_alt_rounded,
            onPressed: _busy
                ? () {}
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SignUpScreen(
                        auth: widget.auth,
                        onSignedIn: widget.onSignedIn,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      children: [
        if (_error != null) AuthMessage(message: _error!),
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
          icon: Icons.lock_outline_rounded,
          obscure: true,
          autofillHints: const [AutofillHints.password],
          validator: (value) =>
              AuthValidators.required(value, 'Enter your password'),
          onSubmitted: (_) => _submit(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: AppTextAction(
            label: 'Forgot password?',
            icon: Icons.help_outline_rounded,
            color: AppColors.textMuted,
            onPressed: _busy
                ? () {}
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ForgotPasswordScreen(auth: widget.auth),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
