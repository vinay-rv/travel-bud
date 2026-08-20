import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's bottom navigation: a floating pill with home and account at its
/// ends, and the screen's primary action raised above its middle.
///
/// The action is a circle rather than a third pill because it is not a place
/// you go — it is the one thing you do here, and it changes with the screen.
/// Its label is the bare noun ("Item", "Stay"); the plus already says "add",
/// and repeating it made every label start with the same word.
class AppBottomBar extends StatelessWidget {
  /// Returns to the trip list. Null when this *is* the trip list, which shows
  /// the slot as the current place rather than somewhere to go.
  final VoidCallback? onHome;

  /// The raised action. Null on a screen with nothing to add.
  final VoidCallback? onAction;

  /// What gets added — "Trip", "Stay", "Item". Not "Add item".
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

  // Kept deliberately tight. The bar reserves its full height from the body,
  // so every pixel here is a pixel off the list above it — on a 360x733 phone
  // this is already a sixth of the screen.
  static const _barHeight = 60.0;

  /// How far the action circle rises above the pill's top edge.
  static const _lift = 24.0;
  static const _circle = 56.0;

  /// Headroom for the glow, which extends past the circle.
  static const _bloom = 8.0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: _bloom + _lift + _barHeight + AppSpacing.sm,
        child: Stack(
          // The circle deliberately sits outside the pill.
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: AppSpacing.gutter,
              right: AppSpacing.gutter,
              bottom: AppSpacing.sm,
              height: _barHeight,
              child: _Pill(
                onHome: onHome,
                onAccount: onAccount,
                label: actionLabel,
                onLabelTap: onAction,
              ),
            ),
            if (onAction != null)
              Positioned(
                top: _bloom,
                left: 0,
                right: 0,
                child: Center(
                  child: AppBottomBarAction(
                    label: actionLabel,
                    icon: actionIcon,
                    size: _circle,
                    onPressed: onAction!,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final VoidCallback? onHome;
  final VoidCallback onAccount;
  final String label;
  final VoidCallback? onLabelTap;

  const _Pill({
    required this.onHome,
    required this.onAccount,
    required this.label,
    required this.onLabelTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _Destination(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              tooltip: 'Home',
              // No handler means this is where you already are.
              selected: onHome == null,
              onTap: onHome,
            ),
          ),
          // The circle covers the middle, so only its label shows here — sunk
          // to the bottom of the pill, clear of the circle above it.
          Expanded(
            child: GestureDetector(
              onTap: onLabelTap,
              behavior: HitTestBehavior.opaque,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: AppBottomBarLabel(label),
                ),
              ),
            ),
          ),
          Expanded(
            child: _Destination(
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              tooltip: 'Account',
              selected: false,
              onTap: onAccount,
            ),
          ),
        ],
      ),
    );
  }
}

/// Names what the plus above it adds.
///
/// Its own widget so it can be told apart from identical words elsewhere on
/// the screen — a trip's "Transport" tab is spelled the same as the bar's
/// label for adding one.
class AppBottomBarLabel extends StatelessWidget {
  final String label;

  const AppBottomBarLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.1,
      ),
    );
  }
}

/// The raised circle: the screen's primary action.
///
/// Its own widget rather than an anonymous button so a caller — and a test —
/// can name it.
class AppBottomBarAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final double size;
  final VoidCallback onPressed;

  const AppBottomBarAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // The visible label sits in the pill below, so the button carries it too
      // rather than announcing itself as an unexplained plus.
      label: 'Add $label',
      child: Tooltip(
        message: 'Add $label',
        child: SizedBox(
          width: size,
          height: size,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: const ShapeDecoration(
                shape: CircleBorder(),
                gradient: _pearl,
                shadows: [
                  // A soft bloom rather than a hard drop shadow: the circle
                  // should look lit, not stuck on.
                  BoxShadow(
                    color: Color(0x59C9D4FF),
                    blurRadius: 26,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Color(0x40FFFFFF),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: Center(
                  child: Icon(icon, size: 26, color: const Color(0xFF2A2F3C)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// An off-white sphere with the light coming from the top left, tinted
  /// towards the app's own accents at the edge so it belongs to this palette
  /// rather than looking like a stock button.
  static const _pearl = RadialGradient(
    center: Alignment(-0.35, -0.45),
    radius: 1.1,
    colors: [
      Color(0xFFFFFFFF),
      Color(0xFFF2F0FF),
      Color(0xFFDCDDFB),
      Color(0xFFC7CCF2),
    ],
    stops: [0.0, 0.42, 0.75, 1.0],
  );
}

class _Destination extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textMuted;

    return Semantics(
      selected: selected,
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Center(
              child: Icon(
                selected ? selectedIcon : icon,
                size: 24,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
