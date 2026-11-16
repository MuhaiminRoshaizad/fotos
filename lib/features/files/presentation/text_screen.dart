import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/bottom_bar_space.dart';

/// Shows a plain-text file. Large files show their first megabyte.
class TextScreen extends StatefulWidget {
  const TextScreen({super.key, required this.path});
  final String path;

  @override
  State<TextScreen> createState() => _TextScreenState();
}

class _TextScreenState extends State<TextScreen> {
  static const int _limit = 1000000;

  // Read once: the page rebuilds as its title collapses into the bar.
  late final Future<(String, bool)> _text = _read();

  Future<(String, bool)> _read() async {
    final RandomAccessFile f = await File(widget.path).open();
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
    return LargeTitleScaffold(
      title: p.basename(widget.path),
      leading: BackBarButton(label: p.basename(p.dirname(widget.path))),
      body: (BuildContext context, Widget header) =>
          FutureBuilder<(String, bool)>(
            future: _text,
            builder: (BuildContext context, AsyncSnapshot<(String, bool)> s) {
              if (s.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    header,
                    const Expanded(
                      child: EmptyState(
                        icon: CupertinoIcons.doc_text,
                        title: 'This file can\'t be read',
                        message: 'Android didn\'t allow opening it.',
                      ),
                    ),
                  ],
                );
              }
              if (!s.hasData) return header;
              final (String text, bool cut) = s.data!;
              return SingleChildScrollView(
                padding: EdgeInsets.only(bottom: bottomClearance(context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    header,
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: SelectableText(
                        cut ? '$text\n\n… Showing the first 1 MB.' : text,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }
}
