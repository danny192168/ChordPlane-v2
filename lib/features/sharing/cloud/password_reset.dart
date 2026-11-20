import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import 'auth_api.dart';

/// Requests a password-reset email from the sign-in sheet or `/reset-password`.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
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
          child: _sent ? _success(theme) : _form(theme),
        ),
      ),
    );
  }

  Widget _form(ThemeData theme) {
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
          'Enter the email you signed up with and we will send a link to '
          'choose a new password.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.alternate_email, size: 20),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            _message!,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Sending…' : 'Send reset link'),
          ),
        ),
      ],
    );
  }

  Widget _success(ThemeData theme) {
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
          'If ${_email.text.trim()} has an account, a reset link is on its '
          'way. Open it on this device to choose a new password.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _close, child: const Text('Done')),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _sent = false;
                  _message = null;
                }),
          child: const Text('Use a different email'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _message = 'Enter a valid email address.');
      return;
    }
    if (AppConfig.supabaseInitError != null) {
      setState(() => _message = AppConfig.supabaseInitError);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await authCall(() => ref.read(signInApiProvider).resetPassword(email));
      if (!mounted) return;
      setState(() => _sent = true);
    } on AuthException catch (error) {
      debugPrint('Password reset failed: ${error.message}');
      if (mounted) setState(() => _message = friendlyAuthMessage(error));
    } catch (error) {
      debugPrint('Password reset failed unexpectedly: $error');
      if (mounted) {
        setState(() => _message = 'Could not reach the server: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _close() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/');
      }
      return;
    }
    Navigator.of(context).maybePop();
  }
}

/// Sets a new password after Supabase's recovery link signs the member in.
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
          'Use at least 8 characters. You will stay signed in on this device.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'New password',
            prefixIcon: Icon(Icons.lock_outline, size: 20),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _confirm,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: 'Confirm new password',
            prefixIcon: Icon(Icons.lock_outline, size: 20),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            _message!,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Saving…' : 'Save new password'),
          ),
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
    if (password.length < 8) {
      _show('Password needs at least 8 characters.');
      return;
    }
    if (password != _confirm.text) {
      _show('The two passwords do not match.');
      return;
    }
    if (AppConfig.supabaseInitError != null) {
      _show(AppConfig.supabaseInitError!);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
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
        _show('This reset link has expired. Request a new one from sign in.');
      } else {
        _show(friendlyAuthMessage(error));
      }
    } catch (error) {
      debugPrint('Password update failed unexpectedly: $error');
      if (mounted) _show('Could not reach the server: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
