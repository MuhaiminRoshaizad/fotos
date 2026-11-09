import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/albums/presentation/album_screen.dart';
import '../features/albums/presentation/albums_screen.dart';
import '../features/albums/presentation/trash_screen.dart';
import '../features/files/presentation/files_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/viewer/presentation/viewer_screen.dart';
import 'shell.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/photos',
    routes: <RouteBase>[
      GoRoute(
        path: '/viewer',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (BuildContext context, GoRouterState state) =>
            CustomTransitionPage<void>(
              key: state.pageKey,
              opaque: false,
              transitionDuration: const Duration(milliseconds: 300),
              reverseTransitionDuration: const Duration(milliseconds: 250),
              // The photo flies in through its Hero; the controls fade in.
              transitionsBuilder: (_, Animation<double> a, _, Widget child) =>
                  FadeTransition(opacity: a, child: child),
              child: ViewerScreen(args: state.extra! as ViewerArgs),
            ),
      ),
      StatefulShellRoute(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell shell,
            ) => AppShell(shell: shell),
        navigatorContainerBuilder:
            (
              BuildContext context,
              StatefulNavigationShell shell,
              List<Widget> children,
            ) => FadeThroughBranches(
              index: shell.currentIndex,
              children: children,
            ),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/photos',
                builder: (_, _) =>
                    const LibraryScreen(kind: LibraryKind.photos),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/videos',
                builder: (_, _) =>
                    const LibraryScreen(kind: LibraryKind.videos),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/albums',
                builder: (_, _) => const AlbumsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'folder/:id',
                    builder: (_, GoRouterState s) =>
                        AlbumScreen(albumId: s.pathParameters['id']!),
                  ),
                  GoRoute(
                    path: 'favourites',
                    builder: (_, _) => const FavouritesScreen(),
                  ),
                  GoRoute(
                    path: 'trash',
                    builder: (_, _) => const TrashScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/files', builder: (_, _) => const FilesScreen()),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
