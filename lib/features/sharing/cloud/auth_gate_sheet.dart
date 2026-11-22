import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/google_auth.dart';
import '../../../core/config/app_config.dart';
import 'auth_api.dart';
import 'auth_widgets.dart';
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
  final _code = TextEditingController();
  bool _createAccount = false;
  bool _busy = false;
  bool _verifyingCode = false;
  String? _emailError;
  String? _passwordError;
  String? _codeError;
  String? _message;
  bool _messageIsError = true;

  /// Set after sign-up (or an unconfirmed/already-registered error) so the
  /// sheet can offer a code field and a resend action for that address.
  String? _confirmationEmail;

  SignInApi get _api => ref.read(signInApiProvider);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
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
            _confirmationEmail != null
                ? 'Confirm your email'
                : _createAccount
                ? 'Create account'
                : 'Sign in',
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
          if (showGoogle && _confirmationEmail == null) ...[
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
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.alternate_email, size: 20),
                    errorText: _emailError,
                  ),
                ),
                const SizedBox(height: 10),
                PasswordField(
                  controller: _password,
                  label: 'Password',
                  isNewPassword: _createAccount,
                  enabled: !_busy,
                  errorText: _passwordError,
                  onSubmitted: _submit,
                ),
              ],
            ),
          ),
          if (_createAccount) ...[
            const SizedBox(height: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _password,
              builder: (context, value, _) =>
                  PasswordStrength(password: value.text),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 10),
            AuthBanner(message: _message!, isError: _messageIsError),
          ],
          if (_confirmationEmail != null) ...[
            const SizedBox(height: 14),
            Text(
              'Open the link in the email, or enter the 6-digit code it '
              'contains.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            EmailCodeField(
              controller: _code,
              enabled: !_verifyingCode,
              errorText: _codeError,
              onSubmitted: _verifyCode,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _verifyingCode ? null : _verifyCode,
                child: _verifyingCode
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ButtonSpinner(),
                          SizedBox(width: 8),
                          Text('Checking…'),
                        ],
                      )
                    : const Text('Confirm email'),
              ),
            ),
            CooldownTextButton(
              label: 'Resend confirmation email',
              busyLabel: 'Sending…',
              onPressed: _resendConfirmation,
            ),
          ] else ...[
            const SizedBox(height: 16),
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
                          Text('Please wait…'),
                        ],
                      )
                    : Text(_createAccount ? 'Create account' : 'Sign in'),
              ),
            ),
          ],
          if (_confirmationEmail == null) ...[
            TextButton(
              onPressed: _busy ? null : _openPasswordReset,
              child: const Text('Forgot password?'),
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
                        _emailError = null;
                        _passwordError = null;
                      }),
                child: Text(
                  _createAccount
                      ? 'I already have an account — sign in instead'
                      : 'New here? Create an account',
                ),
              ),
            ),
          ] else
            TextButton(
              onPressed: _verifyingCode
                  ? null
                  : () => setState(() {
                      _confirmationEmail = null;
                      _message = null;
                      _codeError = null;
                      _code.clear();
                    }),
              child: const Text('Back to sign in'),
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
      if (mounted) _show(describeAuthFailure(error).message);
    } catch (error) {
      debugPrint('Google auth failed unexpectedly: $error');
      if (mounted) _show(offlineAuthMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final emailProblem = isPlausibleEmail(email)
        ? null
        : 'Enter a valid email address.';
    final passwordProblem = password.isEmpty
        ? 'Enter your password.'
        : _createAccount && password.length < minPasswordLength
        ? 'Password needs at least $minPasswordLength characters.'
        : null;
    if (emailProblem != null || passwordProblem != null) {
      setState(() {
        _emailError = emailProblem;
        _passwordError = passwordProblem;
        _message = null;
      });
      return;
    }
    if (AppConfig.supabaseInitError != null) {
      _show(AppConfig.supabaseInitError!);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _emailError = null;
      _passwordError = null;
      _confirmationEmail = null;
    });
    try {
      if (_createAccount) {
        final response = await authCall(() => _api.signUp(email, password));
        if (!mounted) return;
        if (response.session == null) {
          _showConfirmation(email);
          return;
        }
        Navigator.of(context).pop();
        return;
      }
      await authCall(() => _api.signIn(email, password));
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (error) {
      debugPrint('Auth failed: ${error.message}');
      final failure = describeAuthFailure(error);
      if (mounted) {
        if (_createAccount &&
            failure.kind == AuthFailureKind.emailAlreadyRegistered) {
          // Neutral on purpose: the sheet should not confirm whether an
          // address already has an account. Offer the resend action in case
          // the account is real but still unconfirmed.
          _showConfirmation(
            email,
            message:
                'If that email is new, check your inbox to confirm it. If it '
                'already has an account, sign in instead.',
          );
          return;
        }
        if (!_createAccount &&
            failure.kind == AuthFailureKind.emailNotConfirmed) {
          _showConfirmation(email, message: failure.message);
          return;
        }
        _show(failure.message);
      }
    } catch (error) {
      // Anything else (offline, DNS, hanging connection, uninitialized
      // client) must still surface — silent failure looks like a hang.
      debugPrint('Auth failed unexpectedly: $error');
      _show(offlineAuthMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showConfirmation(String email, {String? message}) {
    setState(() {
      _confirmationEmail = email;
      _codeError = null;
      _code.clear();
      _message = message ?? 'Check your inbox — confirm your email, then sign in.';
      _messageIsError = false;
    });
  }

  Future<void> _verifyCode() async {
    final email = _confirmationEmail;
    if (email == null) return;
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() {
        _codeError = 'Enter the 6-digit code from the email.';
        _message = null;
      });
      return;
    }
    setState(() {
      _verifyingCode = true;
      _codeError = null;
      _message = null;
    });
    try {
      await authCall(
        () => _api.verifyEmailCode(
          email: email,
          code: code,
          type: OtpType.signup,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (error) {
      debugPrint('Confirmation code failed: ${error.message}');
      if (!mounted) return;
      final failure = describeAuthFailure(error);
      if (failure.kind == AuthFailureKind.expiredToken) {
        setState(() {
          _codeError = 'That code is not right or has expired. Resend the '
              'email and use the newest code.';
        });
      } else {
        _show(failure.message);
      }
    } catch (error) {
      debugPrint('Confirmation code failed unexpectedly: $error');
      if (mounted) _show(offlineAuthMessage);
    } finally {
      if (mounted) setState(() => _verifyingCode = false);
    }
  }

  Future<bool> _resendConfirmation() async {
    final email = _confirmationEmail;
    if (email == null) return false;
    setState(() {
      _message = null;
      _codeError = null;
    });
    try {
      await authCall(() => _api.resendConfirmation(email));
      _show(
        'Confirmation email sent. Check your inbox (and spam).',
        isError: false,
      );
      return true;
    } on AuthException catch (error) {
      _show(describeAuthFailure(error).message);
      return false;
    } catch (error) {
      debugPrint('Confirmation resend failed: $error');
      _show(offlineAuthMessage);
      return false;
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
    });
  }
}
