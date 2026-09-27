/// A02 — shared teal theme tokens for the auth slice (RailMate BD).
///
/// Binding visual reference: `design/reference/` ref-2 (Welcome/Login/
/// Register) and ref-3 (Verify). Deep teal `#0E5A66` for headers and primary
/// buttons, page background `#F4F7F9`, cards white with radius 16, primary
/// buttons radius 12, inputs light border radius 10 with leading icon.
///
/// This file holds only auth-slice tokens so screens stay consistent. It does
/// not duplicate any app-wide theme (none exists yet — `main.dart` still
/// uses the Flutter template theme).
library;

import 'package:flutter/material.dart';

/// Deep teal used for headers, primary buttons and selected states.
const Color kAuthTeal = Color(0xFF0E5A66);

/// Darker teal for pressed states and gradients.
const Color kAuthTealDark = Color(0xFF0A434C);

/// Success/verified green.
const Color kAuthGreen = Color(0xFF1E9E6A);

/// Danger red (reserved for auth errors / destructive actions).
const Color kAuthDanger = Color(0xFFE5484D);

/// Page background for auth screens.
const Color kAuthPageBg = Color(0xFFF4F7F9);

/// Muted hint / secondary text on auth screens.
const Color kAuthHint = Color(0xFF8A9BA3);

/// Light input border.
const Color kAuthBorder = Color(0xFFE1E8EC);

/// Header block with rounded bottom corners (~24px), white title and a
/// translucent-circle back chevron, per UI_VISUAL_SPEC.
class AuthHeader extends StatelessWidget {
  /// Title shown in the teal header block (e.g. "Log in to RailMate BD").
  final String title;

  /// Subtitle shown under the title.
  final String subtitle;

  /// Whether to show the back chevron. Defaults to true.
  final bool showBack;

  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 56),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[kAuthTealDark, kAuthTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (showBack)
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          if (showBack) const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width teal primary button with trailing arrow, per UI_VISUAL_SPEC.
class AuthPrimaryButton extends StatelessWidget {
  /// Button label.
  final String label;

  /// Called on tap. Null disables the button (with reduced opacity).
  final VoidCallback? onPressed;

  /// Whether an async operation is in progress (shows a spinner).
  final bool loading;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !loading;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: kAuthTeal,
          disabledBackgroundColor: kAuthTeal.withValues(alpha: 0.5),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(label),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ),
      ),
    );
  }
}

/// Labelled input field with light border, radius 10 and a leading icon,
/// per UI_VISUAL_SPEC.
class AuthField extends StatelessWidget {
  /// Field label shown above the input.
  final String label;

  /// Placeholder hint inside the input.
  final String hint;

  /// Leading icon shown inside the input.
  final IconData icon;

  /// Text controller. When null, an internal unmanaged controller is used.
  final TextEditingController? controller;

  /// Whether the text is obscured (passwords).
  final bool obscureText;

  /// Trailing widget (e.g. password visibility toggle).
  final Widget? suffix;

  /// Keyboard type.
  final TextInputType keyboardType;

  /// Validation error text, or null when valid.
  final String? errorText;

  /// Called on every change.
  final ValueChanged<String>? onChanged;

  const AuthField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    this.controller,
    this.obscureText = false,
    this.suffix,
    this.keyboardType = TextInputType.text,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: kAuthHint, fontSize: 14),
            prefixIcon: Icon(icon, color: Colors.black54),
            suffixIcon: suffix,
            errorText: errorText,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kAuthBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kAuthBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kAuthTeal, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Rounded white sheet overlapping the teal header, used by login/register/
/// verify screens to match ref-2/ref-3 card layout.
class AuthSheet extends StatelessWidget {
  /// Sheet content.
  final Widget child;

  const AuthSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
