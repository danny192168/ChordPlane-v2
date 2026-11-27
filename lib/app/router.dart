import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/community/presentation/community_song_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/published_library_screen.dart';
import '../features/library/favorites_screen.dart';
import '../features/library/saved_screen.dart';
import '../features/live/presentation/live_setlist_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/setlists/setlists_screen.dart';
import '../features/setlists/setlist_detail_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sharing/cpl.dart';
import '../features/sharing/cloud/auth_confirm_screen.dart';
import '../features/sharing/cloud/my_shares_screen.dart';
import '../features/sharing/cloud/password_reset.dart';
import '../features/sharing/import_screen.dart';
import '../features/songs/presentation/artist_screen.dart';
import '../features/songs/presentation/online_artist_screen.dart';
import '../features/songs/presentation/song_editor_screen.dart';
import '../features/songs/presentation/song_viewer_screen.dart';
import 'app_shell.dart';
import 'deep_links.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _libraryNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'library');
final _savedNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'saved');
final _favoritesNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'favorites',
);
final _setlistsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'setlists');

/// Where the app should open. Deep links replace this before the router is
/// built; the root route is the default.
final initialLocationProvider = Provider<String>((ref) => '/');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: ref.watch(initialLocationProvider),
    // Flutter passes the raw link (for example `chordplane://c/<code>`) as the
    // platform default location. We normalise it ourselves in [main] instead.
    overridePlatformDefaultLocation: true,
    errorBuilder: (context, state) =>
        _DeepLinkRecovery(location: state.uri.toString()),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _libraryNavigatorKey,
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _savedNavigatorKey,
            routes: [
              GoRoute(
                path: '/saved',
                builder: (context, state) => const SavedScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _favoritesNavigatorKey,
            routes: [
              GoRoute(
                path: '/favorites',
                builder: (context, state) => const FavoritesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _setlistsNavigatorKey,
            routes: [
              GoRoute(
                path: '/setlists',
                builder: (context, state) => const SetlistsScreen(),
              ),
              GoRoute(
                path: '/setlist/:id',
                builder: (context, state) =>
                    SetlistDetailScreen(setlistId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/song/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            SongViewerScreen(songId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/published',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const PublishedLibraryScreen(),
      ),
      GoRoute(
        path: '/community/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => CommunitySongScreen(
          songId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/live/:token',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => LiveSetlistScreen(
          token: state.pathParameters['token']!,
        ),
      ),
      GoRoute(
        path: '/l/:token',
        parentNavigatorKey: rootNavigatorKey,
        redirect: (context, state) =>
            '/live/${Uri.encodeComponent(state.pathParameters['token']!)}',
      ),
      GoRoute(
        path: '/editor',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SongEditorScreen(),
      ),
      GoRoute(
        path: '/editor/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            SongEditorScreen(songId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/artist/:slug',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ArtistScreen(
          slug: state.pathParameters['slug']!,
          favoritesOnly: state.uri.queryParameters['favorites'] == '1',
          savedOnly: state.uri.queryParameters['saved'] == '1',
        ),
      ),
      GoRoute(
        path: '/online-artist/:artist',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => OnlineArtistScreen(
          artist: state.pathParameters['artist']!,
        ),
      ),
      GoRoute(
        path: '/profile',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/my-shares',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const MySharesScreen(),
      ),
      GoRoute(
        path: '/import',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ImportScreen(
          initialCode: state.uri.queryParameters['d'],
          initialToken: state.uri.queryParameters['s'],
          initialFilePath: state.uri.queryParameters['file'],
        ),
      ),
      GoRoute(
        path: '/reset-password',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/auth/confirm',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => AuthConfirmScreen(
          tokenHash: state.uri.queryParameters['token_hash'] ?? '',
          type: state.uri.queryParameters['type'] ?? 'signup',
        ),
      ),
      GoRoute(
        path: '/set-new-password',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SetNewPasswordScreen(),
      ),
      GoRoute(
        path: '/c/:code',
        parentNavigatorKey: rootNavigatorKey,
        redirect: (context, state) =>
            '/import?d=${Uri.encodeComponent(state.pathParameters['code']!)}',
      ),
      GoRoute(
        path: '/s/:token',
        parentNavigatorKey: rootNavigatorKey,
        redirect: (context, state) =>
            '/import?s=${Uri.encodeComponent(state.pathParameters['token']!)}',
      ),
      // Song-level links (/s/<token>/<n>) from the web viewer land in the
      // same import flow; the app always imports the whole bundle.
      GoRoute(
        path: '/s/:token/:song',
        parentNavigatorKey: rootNavigatorKey,
        redirect: (context, state) =>
            '/import?s=${Uri.encodeComponent(state.pathParameters['token']!)}',
      ),
    ],
  );
});

/// Catches raw deep links that Flutter pushes while the app is already
/// running (`didPushRouteInformation` bypasses [GoRouter.initialLocation]),
/// then forwards them to the normalised location.
class _DeepLinkRecovery extends StatefulWidget {
  const _DeepLinkRecovery({required this.location});

  final String location;

  @override
  State<_DeepLinkRecovery> createState() => _DeepLinkRecoveryState();
}

class _DeepLinkRecoveryState extends State<_DeepLinkRecovery> {
  /// Both server-backed links (`…/s/<token>`) and legacy inline codes
  /// (`…/c/<code>`) are recoverable, as are Supabase auth redirects;
  /// anything else is genuinely not found.
  late final bool _isDeepLink =
      CplFormat.extractServerToken(widget.location) != null ||
      CplBundle.extractShareCode(widget.location) != null ||
      isLiveDeepLink(widget.location) ||
      isAuthDeepLink(widget.location);

  @override
  void initState() {
    super.initState();
    if (!_isDeepLink) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      GoRouter.of(context).go(routeForIncomingLink(widget.location));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isDeepLink) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                'There is nothing at "${widget.location}".',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => GoRouter.of(context).go('/'),
                child: const Text('Back to library'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
