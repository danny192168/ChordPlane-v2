import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/google_auth.dart';
import '../../../core/config/app_config.dart';
import 'auth_api.dart';
import 'password_reset.dart';

export 'auth_api.dart';

/// Modal sign-in gate shown when an action requires a cloud account.
///
/// Native Google Sign-In is offered first when a Google client ID was
/// compiled in; email + password always works and needs no extra setup.
Future<void> showSignInGate(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => const _SignInGate(),
  );
}

class _SignInGate extends ConsumerStatefulWidget {
  const _SignInGate();

  @override
  ConsumerState<_SignInGate> createState() => _SignInGateState();
}

class _SignInGateState extends ConsumerState<_SignInGate> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _createAccount = false;
  bool _busy = false;
  String? _message;
  bool _messageIsError = true;

  /// Set after sign-up (or an unconfirmed/already-registered error) so the
  /// sheet can offer a resend action for the address that needs it.
  String? _confirmationEmail;
  bool _sendingConfirmation = false;

  SignInApi get _api => ref.read(signInApiProvider);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showGoogle = ref.watch(googleSignInEnabledProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _createAccount ? 'Create account' : 'Sign in',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'An account is only needed to share with cloud links. Your '
            'library stays on this device either way.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (showGoogle) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('google-sign-in'),
                onPressed: _busy ? null : _signInWithGoogle,
                icon: SvgPicture.asset(
                  'assets/icons/google_g.svg',
                  width: 18,
                  height: 18,
                ),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'or use email',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
          ] else
            const SizedBox(height: 16),
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.alternate_email, size: 20),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline, size: 20),
                  ),
                ),
              ],
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(
              _message!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: _messageIsError
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ],
          if (_confirmationEmail != null) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _sendingConfirmation ? null : _resendConfirmation,
                child: Text(
                  _sendingConfirmation
                      ? 'Sending…'
                      : 'Resend confirmation email',
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(
                _busy
                    ? 'Please wait…'
                    : (_createAccount ? 'Create account' : 'Sign in'),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _openPasswordReset,
              child: const Text('Forgot password?'),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _createAccount = !_createAccount;
                      _message = null;
                      _confirmationEmail = null;
                    }),
              child: Text(
                _createAccount
                    ? 'I already have an account — sign in instead'
                    : 'New here? Create an account',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    if (AppConfig.supabaseInitError != null) {
      _show(AppConfig.supabaseInitError!);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _confirmationEmail = null;
    });
    try {
      final result = await ref.read(googleAuthProvider).signIn();
      await authCall(() => _api.signInWithGoogle(result.idToken));
      if (mounted) Navigator.of(context).pop();
    } on GoogleAuthException catch (error) {
      if (!error.canceled && mounted) _show(error.message);
    } on AuthException catch (error) {
      debugPrint('Google auth failed: ${error.message}');
      if (mounted) _show(friendlyAuthMessage(error));
    } catch (error) {
      debugPrint('Google auth failed unexpectedly: $error');
      if (mounted) _show('Could not reach the server: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || !email.contains('@')) {
      _show('Enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      _show('Password needs at least 8 characters.');
      return;
    }
    if (AppConfig.supabaseInitError != null) {
      _show(AppConfig.supabaseInitError!);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _confirmationEmail = null;
    });
    try {
      if (_createAccount) {
        final response = await authCall(() => _api.signUp(email, password));
        if (!mounted) return;
        if (response.session == null) {
          setState(() => _confirmationEmail = email);
          _show(
            'Check your inbox — confirm your email, then sign in.',
            isError: false,
          );
          return;
        }
        if (mounted) Navigator.of(context).pop();
        return;
      }
      await authCall(() => _api.signIn(email, password));
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (error) {
      debugPrint('Auth failed: ${error.message}');
      final text = error.message.toLowerCase();
      if (_createAccount &&
          (text.contains('already registered') ||
              text.contains('already exists'))) {
        if (mounted) setState(() => _confirmationEmail = email);
      } else if (!_createAccount && text.contains('email not confirmed')) {
        if (mounted) setState(() => _confirmationEmail = email);
      }
      _show(friendlyAuthMessage(error));
    } catch (error) {
      // Anything else (offline, DNS, hanging connection, uninitialized
      // client) must still surface — silent failure looks like a hang.
      debugPrint('Auth failed unexpectedly: $error');
      _show('Could not reach the server: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendConfirmation() async {
    final email = _confirmationEmail;
    if (email == null) return;
    setState(() {
      _sendingConfirmation = true;
      _message = null;
    });
    try {
      await authCall(() => _api.resendConfirmation(email));
      _show(
        'Confirmation email sent. Check your inbox (and spam).',
        isError: false,
      );
    } on AuthException catch (error) {
      _show(friendlyAuthMessage(error));
    } catch (error) {
      _show('Could not send the email: $error');
    } finally {
      if (mounted) setState(() => _sendingConfirmation = false);
    }
  }

  void _openPasswordReset() {
    final router = GoRouter.maybeOf(context);
    final navigator = Navigator.of(context);
    navigator.pop();
    if (router != null) {
      // Push through the router so the reset screen's Done button can pop
      // back to the sheet's origin instead of leaving a stray route behind.
      router.push('/reset-password');
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => const ResetPasswordScreen(),
      ),
    );
  }

  void _show(String message, {bool isError = true}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = isError;
      _busy = false;
    });
  }
}
