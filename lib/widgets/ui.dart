import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Ambient background: the flat canvas plus two soft accent glows, so screens
/// have depth without any heavy chrome.
class AppBackground extends StatelessWidget {
  final Widget child;
  final Color glow;

  const AppBackground({
    super.key,
    required this.child,
    this.glow = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.canvas),
      child: Stack(
        children: [
          Positioned(
            top: -180,
            right: -120,
            child: _Glow(color: glow, size: 380, opacity: 0.16),
          ),
          Positioned(
            top: 220,
            left: -160,
            child: _Glow(color: AppColors.mint, size: 320, opacity: 0.07),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;

  const _Glow({
    required this.color,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// The standard surface container: soft fill, hairline border, big radius.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final Clip clipBehavior;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = AppRadius.lg,
    this.clipBehavior = Clip.none,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? AppColors.border),
    );

    if (onTap == null) {
      return Container(
        decoration: decoration,
        clipBehavior: clipBehavior,
        padding: padding,
        child: child,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        splashColor: AppColors.primary.withValues(alpha: 0.06),
        highlightColor: AppColors.primary.withValues(alpha: 0.04),
        child: Ink(
          decoration: decoration,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Small rounded label — used for counts, statuses, and metadata.
class AppPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool solid;

  const AppPill({
    super.key,
    required this.label,
    this.icon,
    this.color = AppColors.primary,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = solid ? const Color(0xFF0B1020) : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: solid ? color : color.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded square icon tile that fronts most rows and headers.
class AppIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const AppIconTile({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}

/// The Packmate mark — the same art as the launcher icon, on a tinted tile.
class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.24)),
      ),
      child: Image.asset(
        'assets/icon/icon_foreground.png',
        width: size,
        height: size,
        // The tile itself is the branding if the asset ever fails to load.
        errorBuilder: (_, _, _) => Icon(
          Icons.work_rounded,
          size: size * 0.5,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// Uppercase micro-heading that separates blocks inside a screen.
class SectionLabel extends StatelessWidget {
  final String label;
  final Widget? trailing;

  const SectionLabel({super.key, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Slim progress track used for packing progress.
class AppProgressBar extends StatelessWidget {
  final double value;
  final Color color;

  const AppProgressBar({super.key, required this.value, this.color = AppColors.mint});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: 6,
          backgroundColor: AppColors.surfaceHigh,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

/// Centred illustration + copy for "nothing here yet" states.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color accent;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.accent = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: 0.22),
                    accent.withValues(alpha: 0.04),
                  ],
                ),
                border: Border.all(color: accent.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, size: 34, color: accent),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Consistent failure surface for any screen whose load future rejects.
class AppErrorState extends StatelessWidget {
  final String message;

  const AppErrorState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          borderColor: AppColors.rose.withValues(alpha: 0.35),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIconTile(
                icon: Icons.error_outline_rounded,
                color: AppColors.rose,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Something went wrong',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The overflow menu shown on every editable row.
class AppRowMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const AppRowMenu({super.key, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textFaint),
      tooltip: 'More actions',
      padding: EdgeInsets.zero,
      splashRadius: 20,
      onSelected: (value) {
        if (value == 'edit') onEdit();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'edit',
          height: 44,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18, color: AppColors.textMuted),
              SizedBox(width: 10),
              Text('Edit'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          height: 44,
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: AppColors.rose),
              SizedBox(width: 10),
              Text('Delete', style: TextStyle(color: AppColors.rose)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Confirmation dialog with the app's destructive styling.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.rose,
            foregroundColor: const Color(0xFF2A0A11),
            minimumSize: const Size(0, 44),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// Form building blocks
// ---------------------------------------------------------------------------

/// Shared chrome for every create/edit screen: a titled header, a scrolling
/// form body, and a pinned primary action so the save button is always
/// reachable without scrolling.
class AppFormScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<Widget> children;
  final String actionLabel;
  final bool saving;
  final VoidCallback onAction;
  final GlobalKey<FormState> formKey;

  const AppFormScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
    required this.actionLabel,
    required this.saving,
    required this.onAction,
    required this.formKey,
    this.accent = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AppBackground(
        glow: accent,
        child: SafeArea(
          child: Form(
            key: formKey,
            child: Column(
              children: [
                _FormHeader(
                  title: title,
                  subtitle: subtitle,
                  icon: icon,
                  accent: accent,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.xs,
                      AppSpacing.gutter,
                      AppSpacing.xxl,
                    ),
                    children: children,
                  ),
                ),
                _FormFooter(
                  label: actionLabel,
                  saving: saving,
                  onPressed: onAction,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const _FormHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textMuted,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          AppIconTile(icon: icon, color: accent),
        ],
      ),
    );
  }
}

class _FormFooter extends StatelessWidget {
  final String label;
  final bool saving;
  final VoidCallback onPressed;

  const _FormFooter({
    required this.label,
    required this.saving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: FilledButton(
        onPressed: saving ? null : onPressed,
        child: saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.textFaint,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
      ),
    );
  }
}

/// A labelled group of fields inside a form.
class FormSection extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const FormSection({super.key, required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.md,
          ),
          child: SectionLabel(label: label),
        ),
        ...children,
      ],
    );
  }
}

/// A tappable field that opens a picker and displays the chosen value —
/// visually matched to the text inputs beside it.
class AppPickerField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const AppPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textMuted),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textFaint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Explanatory note under a field or section.
class FormHint extends StatelessWidget {
  final String text;

  const FormHint(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: AppColors.textFaint,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
