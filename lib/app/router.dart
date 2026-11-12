import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/library/library_screen.dart';
import '../features/search/search_screen.dart';
import '../features/setlists/setlists_screen.dart';
import '../features/setlists/setlist_detail_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sharing/cpl.dart';
import '../features/sharing/import_screen.dart';
import '../features/songs/presentation/artist_screen.dart';
import '../features/songs/presentation/song_editor_screen.dart';
import '../features/songs/presentation/song_viewer_screen.dart';
import 'app_shell.dart';
import 'deep_links.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _libraryNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'library');
final _searchNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'search');
final _setlistsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'setlists');
final _settingsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'settings');

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
    errorBuilder: (context, state) => _DeepLinkRecovery(
      location: state.uri.toString(),
    ),
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
            navigatorKey: _searchNavigatorKey,
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
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
                builder: (context, state) => SetlistDetailScreen(
                  setlistId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _settingsNavigatorKey,
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
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
        builder: (context, state) =>
            ArtistScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/import',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ImportScreen(
          initialCode: state.uri.queryParameters['d'],
          initialToken: state.uri.queryParameters['s'],
        ),
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
  late final bool _isDeepLink =
      CplBundle.extractShareCode(widget.location) != null;

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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
