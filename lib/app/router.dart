import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/albums/presentation/album_screen.dart';
import '../features/albums/presentation/albums_screen.dart';
import '../features/albums/presentation/empty_album_screen.dart';
import '../features/albums/presentation/trash_screen.dart';
import '../features/files/domain/file_entry.dart';
import '../features/files/presentation/file_media_viewer.dart';
import '../features/files/presentation/files_screen.dart';
import '../features/files/presentation/folder_screen.dart';
import '../features/files/presentation/pdf_screen.dart';
import '../features/files/presentation/text_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/takeout_import/presentation/review_screen.dart';
import '../features/takeout_import/presentation/takeout_home_screen.dart';
import '../features/takeout_import/presentation/takeout_import_screen.dart';
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
      GoRoute(
        path: '/takeout/import',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, GoRouterState s) =>
            TakeoutImportScreen(path: s.uri.queryParameters['path']!),
      ),
      GoRoute(
        path: '/takeout/review',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const ReviewScreen(),
      ),
      GoRoute(
        path: '/files/media',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, GoRouterState state) {
          final (List<FileEntry> items, int index) =
              state.extra! as (List<FileEntry>, int);
          return FileMediaViewer(items: items, index: index);
        },
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
                    path: 'empty',
                    builder: (_, GoRouterState s) =>
                        EmptyAlbumScreen(name: s.uri.queryParameters['name']!),
                  ),
                  GoRoute(
                    path: 'favourites',
                    builder: (_, _) => const FavouritesScreen(),
                  ),
                  GoRoute(
                    path: 'trash',
                    builder: (_, _) => const TrashScreen(),
                  ),
                  GoRoute(
                    path: 'takeout',
                    builder: (_, _) => const TakeoutHomeScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/files',
                builder: (_, _) => const FilesScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'folder',
                    builder: (_, GoRouterState s) =>
                        FolderScreen(path: s.uri.queryParameters['path']!),
                  ),
                  GoRoute(
                    path: 'pdf',
                    builder: (_, GoRouterState s) =>
                        PdfScreen(path: s.uri.queryParameters['path']!),
                  ),
                  GoRoute(
                    path: 'text',
                    builder: (_, GoRouterState s) =>
                        TextScreen(path: s.uri.queryParameters['path']!),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
