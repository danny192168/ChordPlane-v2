import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_api.dart';

/// Redeems the `token_hash` carried by a confirmation or recovery link.
///
/// Supabase signs these links so they can be exchanged without the PKCE
/// verifier that lives on the requesting device. That is what lets someone
/// request a reset on their phone and click the link in their laptop's mail
/// client.
class AuthConfirmScreen extends ConsumerStatefulWidget {
  const AuthConfirmScreen({
    super.key,
    required this.tokenHash,
    required this.type,
  });

  final String tokenHash;
  final String type;

  @override
  ConsumerState<AuthConfirmScreen> createState() => _AuthConfirmScreenState();
}

class _AuthConfirmScreenState extends ConsumerState<AuthConfirmScreen> {
  bool _busy = true;
  String? _error;

  OtpType get _otpType => switch (widget.type.toLowerCase().replaceAll(
    '_',
    '',
  )) {
    'recovery' => OtpType.recovery,
    'invite' => OtpType.invite,
    'magiclink' => OtpType.magiclink,
    'emailchange' => OtpType.emailChange,
    _ => OtpType.signup,
  };

  bool get _isRecovery => _otpType == OtpType.recovery;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _redeem();
    });
  }

  Future<void> _redeem() async {
    if (widget.tokenHash.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'This link is missing its token. Request a new email.';
      });
      return;
    }
    try {
      await authCall(
        () => ref
            .read(signInApiProvider)
            .verifyEmailLink(tokenHash: widget.tokenHash, type: _otpType),
      );
      if (!mounted) return;
      final router = GoRouter.maybeOf(context);
      if (router == null) {
        setState(() => _busy = false);
        return;
      }
      router.go(_isRecovery ? '/set-new-password' : '/');
    } on AuthException catch (error) {
      debugPrint('Auth link failed: ${error.message}');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeAuthFailure(error).message;
        });
      }
    } catch (error) {
      debugPrint('Auth link failed unexpectedly: $error');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = offlineAuthMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm email')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _busy
                  ? const [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Finishing sign-in…'),
                    ]
                  : [
                      Icon(
                        Icons.link_off,
                        size: 44,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'That link did not work',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error ?? 'The link may have expired or been used.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => GoRouter.of(
                            context,
                          ).go(_isRecovery ? '/reset-password' : '/'),
                          child: Text(
                            _isRecovery ? 'Send a new reset email' : 'Back',
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => GoRouter.of(context).go('/'),
                        child: const Text('Back to library'),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}
