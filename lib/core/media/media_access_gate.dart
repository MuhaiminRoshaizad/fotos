import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_tokens.dart';
import '../widgets/empty_state.dart';
import 'media_providers.dart';
import 'media_repository.dart';

/// Shows [child] once fotos may read the photo library, and the explanation
/// and request otherwise. Access is checked again whenever the app resumes,
/// since the user may have changed it in Settings.
class MediaAccessGate extends ConsumerStatefulWidget {
  const MediaAccessGate({super.key, required this.child});

  final Widget child;

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
    return access.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox.shrink(),
      error: (_, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'Couldn\'t check photo access',
        message: 'Android didn\'t answer. Try again.',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(mediaAccessProvider),
      ),
      data: (MediaAccess a) => switch (a) {
        MediaAccess.full => widget.child,
        MediaAccess.limited => Column(
          children: <Widget>[
            const _LimitedBanner(),
            Expanded(child: widget.child),
          ],
        ),
        MediaAccess.denied => EmptyState(
          icon: Icons.photo_library_outlined,
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
