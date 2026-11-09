import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';

enum LibraryKind { photos, videos }

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.kind});

  final LibraryKind kind;

  @override
  Widget build(BuildContext context) {
    final bool photos = kind == LibraryKind.photos;
    return Scaffold(
      appBar: AppBar(title: Text(photos ? 'Photos' : 'Videos')),
      body: EmptyState(
        icon: photos
            ? Icons.photo_library_outlined
            : Icons.video_library_outlined,
        title: photos ? 'No photos yet' : 'No videos yet',
        message: 'Your library appears here.',
      ),
    );
  }
}
