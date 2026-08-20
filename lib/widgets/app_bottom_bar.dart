import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's bottom navigation.
///
/// Three fixed slots: home on the left, the account on the right, and in the
/// middle whatever "add" means on the screen you are looking at — a trip on the
/// home screen, a stay or an item or an expense inside a trip. The middle slot
/// replaces what used to be a floating button, which meant the primary action
/// sat on top of the last row of every list.
///
/// The account lives here rather than in each screen's header: it is the same
/// destination from everywhere, and a header is for what the screen is about.
class AppBottomBar extends StatelessWidget {
  /// Returns to the trip list. Null when this *is* the trip list, which shows
  /// the slot as the current place rather than somewhere to go.
  final VoidCallback? onHome;

  /// The middle slot. Null on a screen with nothing to add, which draws the
  /// slot as empty rather than shifting the other two.
  final VoidCallback? onAction;
  final String actionLabel;
  final IconData actionIcon;

  final VoidCallback onAccount;

  const AppBottomBar({
    super.key,
    required this.onHome,
    required this.onAction,
    required this.actionLabel,
    required this.onAccount,
    this.actionIcon = Icons.add_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              _BottomBarDestination(
                icon: Icons.home_rounded,
                label: 'Home',
                // No handler means this is where you already are.
                selected: onHome == null,
                onTap: onHome,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: onAction == null
                    ? const SizedBox.shrink()
                    : AppBottomBarAction(
                        label: actionLabel,
                        icon: actionIcon,
                        onPressed: onAction!,
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _BottomBarDestination(
                icon: Icons.person_rounded,
                label: 'Account',
                selected: false,
                onTap: onAccount,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The middle slot: the screen's primary "add" action.
///
/// Its own widget rather than an anonymous button so a caller — and a test —
/// can name it.
class AppBottomBarAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const AppBottomBarAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return _GradientActionSurface(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 14,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: AppSpacing.sm),
                // The label changes with the screen, and "Add Transport" is
                // wider than "Add Item" — so it shrinks rather than overflows.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The gradient fill and lit top edge the primary buttons share.
class _GradientActionSurface extends StatelessWidget {
  final Widget child;

  const _GradientActionSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppGradients.primaryButton,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: const Border(
          top: BorderSide(color: AppGradients.buttonHighlight),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDeep.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _BottomBarDestination extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _BottomBarDestination({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textMuted;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
