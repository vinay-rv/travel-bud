import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Shared chrome for the sign-in, sign-up, verify and reset screens, so the
/// whole entry flow feels like one thing rather than four.
class AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;
  final String actionLabel;
  final bool busy;
  final VoidCallback onAction;
  final GlobalKey<FormState> formKey;
  final Widget? footer;
  final bool showBack;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
    required this.actionLabel,
    required this.busy,
    required this.onAction,
    required this.formKey,
    this.footer,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      resizeToAvoidBottomInset: true,
      body: AppBackground(
        child: SafeArea(
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.sm,
                AppSpacing.gutter,
                AppSpacing.xxl,
              ),
              children: [
                Row(
                  children: [
                    if (showBack)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: AppColors.textMuted,
                        tooltip: 'Back',
                        onPressed: busy
                            ? null
                            : () => Navigator.of(context).maybePop(),
                      )
                    else
                      const SizedBox(width: AppSpacing.xs),
                    const Spacer(),
                    AppIconTile(icon: icon, color: AppColors.primary),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(title, style: theme.textTheme.displaySmall),
                const SizedBox(height: AppSpacing.sm),
                Text(subtitle, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xxl),
                ...children,
                const SizedBox(height: AppSpacing.xl),
                AppPrimaryButton(
                  label: actionLabel,
                  icon: Icons.arrow_forward_rounded,
                  loading: busy,
                  onPressed: busy ? null : onAction,
                ),
                if (footer != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Field styling shared by every credential input.
class AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;
  final bool autofocus;
  final List<String>? autofillHints;

  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.onSubmitted,
    this.autofocus = false,
    this.autofillHints,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        autofocus: autofocus,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        autocorrect: false,
        enableSuggestions: !obscure,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
        ),
        validator: validator,
        onFieldSubmitted: onSubmitted,
      ),
    );
  }
}

/// A short message under the form — an error, or a confirmation.
class AuthMessage extends StatelessWidget {
  final String message;
  final bool isError;

  const AuthMessage({super.key, required this.message, this.isError = true});

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.rose : AppColors.mint;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        borderColor: color.withValues(alpha: 0.35),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline,
              size: 18,
              color: color,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared validators. Kept here so sign-up and reset agree on what a password
/// is, and so the rules match the API's — a client that accepts less than the
/// server does produces confusing 400s.
class AuthValidators {
  AuthValidators._();

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter your email address';
    // Deliberately loose: the only real proof an address works is that the
    // confirmation code arrives.
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
      return 'That does not look like an email address';
    }
    return null;
  }

  static String? password(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Choose a password';
    // Length, not composition: "Password1!" satisfies most complexity rules and
    // is trivially guessable, while a long phrase is not.
    if (text.length < 10) return 'Use at least 10 characters';
    return null;
  }

  static String? required(String? value, String message) =>
      (value?.trim().isEmpty ?? true) ? message : null;

  static String? code(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter the 6-digit code';
    if (!RegExp(r'^\d{6}$').hasMatch(text)) return 'The code is 6 digits';
    return null;
  }
}
