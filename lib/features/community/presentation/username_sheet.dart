import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_gateway.dart';
import '../data/community_api.dart';

/// Returns true once a unique username has been saved. Publishing and rating
/// both call this so older accounts can pick a name before they take part.
Future<bool> showUsernameSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => const _UsernameSheet(),
  );
  return result ?? false;
}

class _UsernameSheet extends ConsumerStatefulWidget {
  const _UsernameSheet();

  @override
  ConsumerState<_UsernameSheet> createState() => _UsernameSheetState();
}

class _UsernameSheetState extends ConsumerState<_UsernameSheet> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
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
            'Choose a username',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'This name credits your Public Library uploads. It is unique, and '
            'changing it updates songs you published before.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: !_busy,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Username',
              hintText: 'guitarjane',
              prefixText: '@',
              errorText: _error,
              helperText: '3–20 letters, numbers or underscores',
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save username'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final candidate = _controller.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_]{3,20}$').hasMatch(candidate)) {
      setState(
        () => _error = 'Use 3–20 letters, numbers or underscores.',
      );
      return;
    }
    if (!ref.read(authGatewayProvider).isSignedIn) {
      setState(() => _error = 'Sign in first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(communityApiProvider);
      final check = await api.checkUsername(candidate);
      if (check['available'] != true) {
        if (mounted) {
          setState(() => _error = (check['reason'] as String?) ?? 'Unavailable.');
        }
        return;
      }
      final saved = await api.setUsername(candidate);
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = 'Could not save that username.');
      }
    } on CommunityException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No connection. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
