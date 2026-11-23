import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_api.dart';

/// Minimum password length the app asks for. Supabase's project setting is
/// the real enforcement; this keeps the client from submitting something the
/// server will reject, and matches the recommendation in the README.
const int minPasswordLength = 10;

/// Deliberately loose: enough to catch "not-an-email" and typos, without
/// rejecting valid-but-unusual addresses the server would accept.
bool isPlausibleEmail(String value) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

/// `danny@example.com` -> `da•••@example.com`, so success screens can show
/// which address received the email without printing it in full.
String maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 0) return email;
  final name = email.substring(0, at);
  final shown = name.length <= 2 ? name.substring(0, 1) : name.substring(0, 2);
  final dots = '•' * (name.length - shown.length).clamp(1, 5);
  return '$shown$dots${email.substring(at)}';
}

/// A text button that locks itself for [cooldown] after a successful press.
///
/// The cooldown is deliberately UX only: Supabase Auth enforces the real
/// window server-side, so pressing again would just produce a 429. Showing a
/// countdown makes that limit legible instead of surprising.
class CooldownTextButton extends StatefulWidget {
  const CooldownTextButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.cooldown = authResendCooldown,
    this.busyLabel = 'Sending…',
    this.alignment = Alignment.centerLeft,
  });

  /// Returns `true` when the request was accepted, which starts the cooldown.
  /// Return `false` (or throw) to leave the button immediately usable.
  final Future<bool> Function() onPressed;

  final String label;
  final String busyLabel;
  final Duration cooldown;
  final Alignment alignment;

  @override
  State<CooldownTextButton> createState() => _CooldownTextButtonState();
}

class _CooldownTextButtonState extends State<CooldownTextButton> {
  Timer? _ticker;
  int _remaining = 0;
  bool _busy = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _handle() async {
    if (_busy || _remaining > 0) return;
    setState(() => _busy = true);
    var accepted = false;
    try {
      accepted = await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || !accepted) return;
    _startCooldown();
  }

  void _startCooldown() {
    _ticker?.cancel();
    final seconds = widget.cooldown.inSeconds;
    if (seconds <= 0) return;
    setState(() => _remaining = seconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining -= 1);
      if (_remaining <= 0) {
        timer.cancel();
        _ticker = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _busy || _remaining > 0;
    final text = _busy
        ? widget.busyLabel
        : _remaining > 0
        ? '${widget.label} in ${_remaining}s'
        : widget.label;
    return Align(
      alignment: widget.alignment,
      child: TextButton(onPressed: blocked ? null : _handle, child: Text(text)),
    );
  }
}

/// Password input with a visibility toggle and room for an inline error.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.isNewPassword = false,
    this.errorText,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final bool isNewPassword;
  final String? errorText;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;
  final bool enabled;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [
        widget.isNewPassword
            ? AutofillHints.newPassword
            : AutofillHints.password,
      ],
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted == null
          ? null
          : (_) => widget.onSubmitted!(),
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline, size: 20),
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: _obscured ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _obscured = !_obscured),
          icon: Icon(
            _obscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 20,
          ),
        ),
      ),
    );
  }
}

/// Six-digit code entry used by both sign-up confirmation and recovery.
///
/// The field is a single input styled to read as a code: paste-friendly,
/// numeric keyboard, and recognised by Android/iOS one-time-code autofill.
class EmailCodeField extends StatelessWidget {
  const EmailCodeField({
    super.key,
    required this.controller,
    this.errorText,
    this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String? errorText;
  final VoidCallback? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      style: const TextStyle(
        fontSize: 24,
        letterSpacing: 10,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: '6-digit code',
        hintText: '000000',
        errorText: errorText,
        prefixIcon: const Icon(Icons.pin_outlined, size: 20),
      ),
    );
  }
}

/// Inline status line for the auth sheets: red for failures, tinted for
/// confirmations that are not errors (for example "check your inbox").
class AuthBanner extends StatelessWidget {
  const AuthBanner({super.key, required this.message, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isError
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = isError
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.mark_email_read_outlined,
            size: 18,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three-segment strength meter with a plain-language caption. Informational
/// only: the server's password policy remains the source of truth.
class PasswordStrength extends StatelessWidget {
  const PasswordStrength({super.key, required this.password});

  final String password;

  int get _score {
    if (password.isEmpty) return 0;
    var score = 0;
    if (password.length >= minPasswordLength) score += 1;
    if (password.length >= 14) score += 1;
    final mixed =
        password.contains(RegExp('[a-z]')) &&
        password.contains(RegExp('[A-Z]'));
    final varied =
        password.contains(RegExp('[^A-Za-z0-9]')) ||
        (mixed && password.contains(RegExp('[0-9]')));
    if (varied) score += 1;
    return score;
  }

  String get _label {
    if (password.isEmpty) return '';
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters.';
    }
    return switch (_score) {
      <= 1 => 'Okay — longer would be safer.',
      2 => 'Good password.',
      _ => 'Strong password.',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final active = password.length >= minPasswordLength
        ? scheme.primary
        : scheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(3, (index) {
            final filled = index < _score;
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
                decoration: BoxDecoration(
                  color: filled ? active : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text(
          _label,
          style: TextStyle(
            fontSize: 11.5,
            color: password.length >= minPasswordLength
                ? scheme.onSurfaceVariant
                : scheme.error,
          ),
        ),
      ],
    );
  }
}

/// Counts down to [until] and then tells the parent the wait is over.
///
/// The sheet keeps its Sign in button disabled while this is on screen, so a
/// scripted attempt cannot just ignore the throttle by pressing again.
class RetryCountdown extends StatefulWidget {
  const RetryCountdown({
    super.key,
    required this.until,
    this.onExpired,
    this.prefix = 'Too many attempts.',
  });

  final DateTime until;
  final VoidCallback? onExpired;
  final String prefix;

  @override
  State<RetryCountdown> createState() => _RetryCountdownState();
}

class _RetryCountdownState extends State<RetryCountdown> {
  Timer? _ticker;
  int _seconds = 0;
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(RetryCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.until != widget.until) {
      _notified = false;
      _restart();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static int _secondsUntil(DateTime until) {
    final remaining = until.difference(DateTime.now()).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  void _restart() {
    _ticker?.cancel();
    _seconds = _secondsUntil(widget.until);
    if (_seconds <= 0) {
      _expire();
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // Prefer the real remaining time so a backgrounded app catches up, but
      // never stall: in tests (and if the clock is unavailable) each tick still
      // makes progress.
      final actual = _secondsUntil(widget.until);
      final stepped = _seconds - 1;
      setState(() => _seconds = actual < stepped ? actual : stepped);
      if (_seconds <= 0) _expire();
    });
  }

  void _expire() {
    _ticker?.cancel();
    _ticker = null;
    if (_notified) return;
    _notified = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onExpired?.call();
    });
  }

  static String _format(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  @override
  Widget build(BuildContext context) {
    if (_seconds <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_outlined, size: 16, color: scheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${widget.prefix} Try again in ${_format(_seconds)}.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The spinner used inside filled buttons so the label stays put.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color;
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: color == null ? null : AlwaysStoppedAnimation(color),
      ),
    );
  }
}
