import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';

class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Files')),
      body: const EmptyState(
        icon: Icons.folder_outlined,
        title: 'No files yet',
        message: 'Every folder on your phone appears here.',
      ),
    );
  }
}
