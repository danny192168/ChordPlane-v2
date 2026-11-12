import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';

/// How long an auth request may run before the sheet gives up with a
/// visible message. The SDK itself has no timeout. Mutable so tests can
/// shrink it; always assign back after changing.
Duration authCallTimeout = const Duration(seconds: 15);

/// Resolves the Supabase auth client. Overridable in tests with a client
/// pointed at a local fake server.
final authClientProvider = Provider<GoTrueClient>((ref) {
  if (AppConfig.supabaseInitError != null || !AppConfig.hasSupabase) {
    throw StateError(AppConfig.supabaseInitError ?? 'Cloud is not configured.');
  }
  return Supabase.instance.client.auth;
});

/// Modal sign-in gate shown when an action requires a cloud account.
///
/// Email + password is offered first because it needs no external provider
/// configuration; magic-link and social providers can be added to the
/// Supabase project later and surfaced here.
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

  GoTrueClient get _auth => ref.read(authClientProvider);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
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
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
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
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline, size: 20),
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
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Please wait…' : (_createAccount
                  ? 'Create account'
                  : 'Sign in')),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _createAccount = !_createAccount;
                      _message = null;
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
    });
    try {
      if (_createAccount) {
        final response = await _authCall(
          () => _auth.signUp(email: email, password: password),
        );
        if (!mounted) return;
        if (response.session == null) {
          _show(
            'Check your inbox — confirm your email, then sign in.',
            isError: false,
          );
          return;
        }
        if (mounted) Navigator.of(context).pop();
        return;
      }
      await _authCall(
        () => _auth.signInWithPassword(email: email, password: password),
      );
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (error) {
      debugPrint('Auth failed: ${error.message}');
      _show(_friendlyAuthMessage(error));
    } catch (error) {
      // Anything else (offline, DNS, hanging connection, uninitialized
      // client) must still surface — silent failure looks like a hang.
      debugPrint('Auth failed unexpectedly: $error');
      _show('Could not reach the server: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The Supabase SDK has no request timeout, so a black-holed connection
  /// would spin forever. Bound every call and translate the timeout into
  /// an [AuthException] so the normal error path handles it.
  Future<T> _authCall<T>(Future<T> Function() call) {
    return call().timeout(
      authCallTimeout,
      onTimeout: () => throw const AuthException(
        'The server took too long to respond. Check your connection and '
        'the project URL, then try again.',
      ),
    );
  }

  String _friendlyAuthMessage(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'Wrong email or password.';
    }
    if (message.contains('email not confirmed')) {
      return 'Confirm your email first — check your inbox (and spam).';
    }
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Too many attempts — wait a minute and try again.';
    }
    if (message.contains('invalid api key') ||
        message.contains('apikey')) {
      return 'The app is configured with a bad API key.';
    }
    return error.message;
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
