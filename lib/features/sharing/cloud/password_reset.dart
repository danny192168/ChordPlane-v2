import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import 'auth_api.dart';
import 'auth_widgets.dart';

/// Requests a password-reset email from the sign-in sheet or `/reset-password`.
///
/// The email carries both a link and (once the project template includes
/// `{{ .Token }}`) a six-digit code. The code path is what makes recovery work
/// when the email is opened on a different device: the PKCE verifier lives on
/// the phone that asked, so a link exchanged elsewhere would fail.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _emailError;
  String? _codeError;
  String? _message;
  bool _messageIsError = true;
  String _sentTo = '';

  SignInApi get _api => ref.read(signInApiProvider);

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _sent ? _sentView(theme) : _requestView(theme),
        ),
      ),
    );
  }

  Widget _requestView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Forgot your password?',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter the email you signed up with and we will send a link and a '
          '6-digit code to choose a new password.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitEmail(),
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: const Icon(Icons.alternate_email, size: 20),
            errorText: _emailError,
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          AuthBanner(message: _message!, isError: _messageIsError),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _submitEmail,
            child: _busy
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ButtonSpinner(),
                      SizedBox(width: 8),
                      Text('Sending…'),
                    ],
                  )
                : const Text('Send reset email'),
          ),
        ),
      ],
    );
  }

  Widget _sentView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 44,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          'Check your inbox',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'If ${maskEmail(_sentTo)} has an account, a reset email is on its '
          'way. Open the link on any device, or type the 6-digit code below.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        EmailCodeField(
          controller: _code,
          enabled: !_busy,
          errorText: _codeError,
          onSubmitted: _submitCode,
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          AuthBanner(message: _message!, isError: _messageIsError),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _submitCode,
            child: _busy
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ButtonSpinner(),
                      SizedBox(width: 8),
                      Text('Checking…'),
                    ],
                  )
                : const Text('Continue'),
          ),
        ),
        const SizedBox(height: 4),
        CooldownTextButton(
          label: 'Resend email',
          busyLabel: 'Sending…',
          onPressed: _resend,
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _sent = false;
                  _message = null;
                  _codeError = null;
                  _code.clear();
                }),
          child: const Text('Use a different email'),
        ),
      ],
    );
  }

  Future<void> _submitEmail() async {
    final email = _email.text.trim();
    if (!isPlausibleEmail(email)) {
      setState(() {
        _emailError = 'Enter a valid email address.';
        _message = null;
      });
      return;
    }
    if (AppConfig.supabaseInitError != null) {
      setState(() => _message = AppConfig.supabaseInitError);
      return;
    }
    setState(() {
      _busy = true;
      _emailError = null;
      _message = null;
    });
    try {
      await authCall(() => _api.resetPassword(email));
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sentTo = email;
        _message = null;
        _messageIsError = true;
        _codeError = null;
        _code.clear();
      });
    } on AuthException catch (error) {
      debugPrint('Password reset failed: ${error.message}');
      if (mounted) _show(describeAuthFailure(error).message);
    } catch (error) {
      debugPrint('Password reset failed unexpectedly: $error');
      if (mounted) _show(offlineAuthMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _resend() async {
    setState(() => _message = null);
    try {
      await authCall(() => _api.resetPassword(_sentTo));
      if (mounted) {
        _show(
          'Reset email sent again. Check your inbox (and spam).',
          isError: false,
        );
      }
      return true;
    } on AuthException catch (error) {
      if (mounted) _show(describeAuthFailure(error).message);
      return false;
    } catch (error) {
      debugPrint('Password reset resend failed: $error');
      if (mounted) _show(offlineAuthMessage);
      return false;
    }
  }

  Future<void> _submitCode() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() {
        _codeError = 'Enter the 6-digit code from the email.';
        _message = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _codeError = null;
      _message = null;
    });
    try {
      await authCall(
        () => _api.verifyEmailCode(
          email: _sentTo,
          code: code,
          type: OtpType.recovery,
        ),
      );
      if (!mounted) return;
      _go('/set-new-password');
    } on AuthException catch (error) {
      debugPrint('Recovery code failed: ${error.message}');
      if (!mounted) return;
      final failure = describeAuthFailure(error);
      if (failure.kind == AuthFailureKind.expiredToken ||
          failure.kind == AuthFailureKind.badToken) {
        setState(() {
          _codeError = 'That code is not right or has expired. Try the '
              'latest email, or resend a new code.';
        });
      } else {
        _show(failure.message);
      }
    } catch (error) {
      debugPrint('Recovery code failed unexpectedly: $error');
      if (mounted) _show(offlineAuthMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _go(String location) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go(location);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const SetNewPasswordScreen()),
    );
  }

  void _show(String message, {bool isError = true}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }
}

/// Sets a new password after a recovery link or code has signed the member in.
class SetNewPasswordScreen extends ConsumerStatefulWidget {
  const SetNewPasswordScreen({super.key});

  @override
  ConsumerState<SetNewPasswordScreen> createState() =>
      _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends ConsumerState<SetNewPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _updated = false;
  bool _expired = false;
  String? _passwordError;
  String? _confirmError;
  String? _message;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a new password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _updated ? _success(theme) : _form(theme),
        ),
      ),
    );
  }

  Widget _form(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose a new password',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Use at least $minPasswordLength characters. You will stay signed '
          'in on this device.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        PasswordField(
          controller: _password,
          label: 'New password',
          isNewPassword: true,
          enabled: !_busy,
          errorText: _passwordError,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _password,
          builder: (context, value, _) =>
              PasswordStrength(password: value.text),
        ),
        const SizedBox(height: 12),
        PasswordField(
          controller: _confirm,
          label: 'Confirm new password',
          isNewPassword: true,
          enabled: !_busy,
          errorText: _confirmError,
          onSubmitted: _submit,
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          AuthBanner(message: _message!),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ButtonSpinner(),
                      SizedBox(width: 8),
                      Text('Saving…'),
                    ],
                  )
                : const Text('Save new password'),
          ),
        ),
        if (_expired)
          TextButton(
            onPressed: _requestNewLink,
            child: const Text('Send a new reset email'),
          ),
      ],
    );
  }

  Widget _success(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 44,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          'Password updated',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'You are signed in and can create cloud links again.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _close, child: const Text('Continue')),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final password = _password.text;
    var valid = true;
    if (password.length < minPasswordLength) {
      setState(() {
        _passwordError = 'Password needs at least $minPasswordLength characters.';
        _confirmError = null;
        _message = null;
      });
      valid = false;
    }
    if (password != _confirm.text) {
      setState(() {
        _confirmError = 'The two passwords do not match.';
        _message = null;
      });
      valid = false;
    }
    if (!valid) return;
    if (AppConfig.supabaseInitError != null) {
      setState(() => _message = AppConfig.supabaseInitError);
      return;
    }
    setState(() {
      _busy = true;
      _passwordError = null;
      _confirmError = null;
      _message = null;
      _expired = false;
    });
    try {
      await authCall(
        () => ref.read(signInApiProvider).updatePassword(password),
      );
      if (!mounted) return;
      setState(() => _updated = true);
    } on AuthException catch (error) {
      debugPrint('Password update failed: ${error.message}');
      if (!mounted) return;
      if (error is AuthSessionMissingException ||
          error.message.toLowerCase().contains('session missing')) {
        setState(() {
          _expired = true;
          _message = 'This reset link has expired. Request a new one from '
              'sign in.';
        });
      } else {
        _show(describeAuthFailure(error).message);
      }
    } catch (error) {
      debugPrint('Password update failed unexpectedly: $error');
      if (mounted) _show(offlineAuthMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _requestNewLink() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go('/reset-password');
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (context) => const ResetPasswordScreen()),
    );
  }

  void _close() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go('/');
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _show(String message) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _busy = false;
    });
  }
}
