import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/albums/presentation/albums_screen.dart';
import '../features/files/presentation/files_screen.dart';
import '../features/library/presentation/library_screen.dart';
import 'shell.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/photos',
    routes: <RouteBase>[
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
              GoRoute(path: '/albums', builder: (_, _) => const AlbumsScreen()),
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
