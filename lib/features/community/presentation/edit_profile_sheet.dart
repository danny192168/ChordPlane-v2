import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/config/app_config.dart';
import '../../songs/data/song_providers.dart';
import '../data/community_api.dart';

/// Display-name editor. Usernames are public identifiers and are managed by
/// their own flow; this sheet only changes the name shown on the profile.
Future<void> showEditProfileSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => const _EditProfileSheet(),
  );
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet();

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _controller;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final current = ref.read(profileInfoProvider).value?.displayName ?? '';
    _controller = TextEditingController(
      text: current.isNotEmpty ? current : ref.read(profileNameProvider),
    );
  }

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
            'Edit profile',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'This name appears on your profile and as the seed for your '
            'avatar. Your username stays the same.',
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
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Display name',
              hintText: 'Guitar Jane',
              errorText: _error,
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
                  : const Text('Save name'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a display name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    String? syncNote;
    final cloudReady =
        AppConfig.hasSupabase && AppConfig.supabaseInitError == null;
    final signedIn =
        ref.read(signedInProvider).value ??
        ref.read(authGatewayProvider).isSignedIn;
    if (cloudReady && signedIn) {
      try {
        await ref.read(communityApiProvider).setDisplayName(name);
      } on CommunityException catch (error) {
        syncNote = '${error.message} Saved on this device.';
      } catch (_) {
        syncNote = 'Saved on this device. Cloud sync will retry later.';
      }
    }

    ref.read(profileNameProvider.notifier).set(name);
    ref.invalidate(profileInfoProvider);
    if (!mounted) return;
    Navigator.pop(context);
    if (syncNote != null) {
      messenger.showSnackBar(SnackBar(content: Text(syncNote)));
    }
  }
}
