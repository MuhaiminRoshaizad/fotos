import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';

/// Shows a plain-text file. Large files show their first megabyte.
class TextScreen extends StatelessWidget {
  const TextScreen({super.key, required this.path});
  final String path;

  static const int _limit = 1000000;

  Future<(String, bool)> _read() async {
    final RandomAccessFile f = await File(path).open();
    try {
      final int length = await f.length();
      final List<int> bytes = await f.read(_limit);
      return (utf8.decode(bytes, allowMalformed: true), length > _limit);
    } finally {
      await f.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(p.basename(path))),
      body: FutureBuilder<(String, bool)>(
        future: _read(),
        builder: (BuildContext context, AsyncSnapshot<(String, bool)> s) {
          if (s.hasError) {
            return const EmptyState(
              icon: CupertinoIcons.doc_text,
              title: 'This file can\'t be read',
              message: 'Android didn\'t allow opening it.',
            );
          }
          if (!s.hasData) return const SizedBox.shrink();
          final (String text, bool cut) = s.data!;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppNavMetrics.clearance(MediaQuery.paddingOf(context).bottom),
            ),
            child: SelectableText(
              cut ? '$text\n\n… Showing the first 1 MB.' : text,
              style: const TextStyle(fontFamily: 'monospace', height: 1.5),
            ),
          );
        },
      ),
    );
  }
}
