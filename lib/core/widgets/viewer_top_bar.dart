import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoIcons;
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'viewer_glass.dart';

/// The top bar of every full-screen viewer: a glass back button, a title
/// over a smaller line, and an optional glass button on the right, on a
/// fade so white text reads over any picture. Place it in a [Stack] over
/// the content; it fades out, and stops taking touches, when [visible] is
/// false.
class ViewerTopBar extends StatelessWidget {
  const ViewerTopBar({
    super.key,
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.onClose,
    this.trailing,
  });

  final bool visible;
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.short,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x8C000000), Color(0x00000000)],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                // NavigationToolbar fills whatever height it is given, so the
                // bar needs its own or it covers the whole picture.
                child: SizedBox(
                  height: 48,
                  child: NavigationToolbar(
                    leading: ViewerGlass(
                      shape: const CircleBorder(),
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        onPressed: onClose,
                        child: const Icon(
                          CupertinoIcons.chevron_back,
                          color: Colors.white,
                          semanticLabel: 'Close',
                        ),
                      ),
                    ),
                    trailing: trailing,
                    middle: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
