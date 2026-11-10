import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_tokens.dart';
import '../widgets/empty_state.dart';
import 'media_providers.dart';
import 'media_repository.dart';

/// Builds the page once fotos may read the photo library, and the
/// explanation and request otherwise. Access is checked again whenever the
/// app resumes, since the user may have changed it in Settings.
///
/// [header] (a large title) heads every state: [builder] receives it to
/// scroll with the content, with the limited-access notice under it.
class MediaAccessGate extends ConsumerStatefulWidget {
  const MediaAccessGate({
    super.key,
    required this.builder,
    this.header = const SizedBox.shrink(),
  });

  final Widget header;
  final Widget Function(Widget header) builder;

  @override
  ConsumerState<MediaAccessGate> createState() => _MediaAccessGateState();
}

class _MediaAccessGateState extends ConsumerState<MediaAccessGate> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () => ref.read(mediaAccessProvider.notifier).recheck(),
  );
  bool _askedOnce = false;

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    await ref.read(mediaAccessProvider.notifier).request();
    if (mounted) setState(() => _askedOnce = true);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<MediaAccess> access = ref.watch(mediaAccessProvider);
    Widget headed(Widget state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        widget.header,
        Expanded(child: state),
      ],
    );
    return access.when(
      skipLoadingOnRefresh: true,
      loading: () => headed(const SizedBox.shrink()),
      error: (_, _) => headed(
        EmptyState(
          icon: CupertinoIcons.exclamationmark_circle,
          title: 'Couldn\'t check photo access',
          message: 'Android didn\'t answer. Try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(mediaAccessProvider),
        ),
      ),
      data: (MediaAccess a) => switch (a) {
        MediaAccess.full => widget.builder(widget.header),
        MediaAccess.limited => widget.builder(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[widget.header, const _LimitedBanner()],
          ),
        ),
        MediaAccess.denied => headed(
          EmptyState(
            icon: CupertinoIcons.photo_on_rectangle,
            title: 'Let fotos show your photos',
            message: _askedOnce
                ? 'Access is off. Turn on Photos and videos for fotos in '
                      'Settings, then come back.'
                : 'fotos shows the photos and videos on this phone. Nothing '
                      'leaves the phone.',
            actionLabel: _askedOnce ? 'Open settings' : 'Allow access',
            onAction: _askedOnce
                ? () => ref.read(mediaRepositoryProvider).openAppSettings()
                : _request,
          ),
        ),
      },
    );
  }
}

class _LimitedBanner extends ConsumerWidget {
  const _LimitedBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'fotos can see only the photos you picked.',
            style: TextStyle(color: cs.onPrimaryContainer),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => ref
                    .read(mediaRepositoryProvider)
                    .pickMoreForLimitedAccess(),
                child: const Text('Pick more'),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(mediaRepositoryProvider).openAppSettings(),
                child: const Text('Allow all photos'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
