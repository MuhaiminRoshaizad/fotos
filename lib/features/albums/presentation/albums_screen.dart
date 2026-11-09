import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';

class AlbumsScreen extends StatelessWidget {
  const AlbumsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Albums')),
      body: const EmptyState(
        icon: Icons.photo_album_outlined,
        title: 'No albums yet',
        message: 'The folders on your phone appear here.',
      ),
    );
  }
}
