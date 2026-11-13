import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSlidingSegmentedControl, CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../../core/format/formatters.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../domain/widget_config.dart';

/// The screen Android opens when a fotos photo widget is placed, and again
/// from its long-press menu: what the widget shows, from where, in what
/// order and how often. Done keeps the widget; Cancel, or going back,
/// leaves no widget behind.
class WidgetSetupScreen extends ConsumerStatefulWidget {
  const WidgetSetupScreen({
    super.key,
    required this.initial,
    required this.onDone,
    required this.onCancel,
  });

  /// The widget's saved settings, or null for a new widget.
  final WidgetConfig? initial;
  final ValueChanged<WidgetConfig> onDone;
  final VoidCallback onCancel;

  @override
  ConsumerState<WidgetSetupScreen> createState() => _WidgetSetupScreenState();
}

class _WidgetSetupScreenState extends ConsumerState<WidgetSetupScreen> {
  late WidgetConfig _c = widget.initial ?? const WidgetConfig();

  void _set(WidgetConfig c) => setState(() => _c = c);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Album>> albums = ref.watch(albumsProvider);
    return LargeTitleScaffold(
      title: 'Photo widget',
      subtitle: 'Resize it on the home screen to change its size.',
      grouped: true,
      leading: BarButton.text(label: 'Cancel', onPressed: widget.onCancel),
      trailing: <Widget>[
        BarButton.text(
          label: 'Done',
          prominent: true,
          onPressed: _c.complete ? () => widget.onDone(_c) : null,
        ),
      ],
      body: (BuildContext context, Widget header) => ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
        ),
        children: <Widget>[
          header,
          _Segments<WidgetShow>(
            heading: 'Show',
            value: _c.show,
            labels: const <WidgetShow, String>{
              WidgetShow.photos: 'Photos',
              WidgetShow.videos: 'Videos',
              WidgetShow.both: 'Both',
            },
            footer: switch (_c.show) {
              WidgetShow.photos => 'Photos and Motion Photos.',
              WidgetShow.videos =>
                'Each video shows its opening frame and length. Tap it to '
                    'play it in fotos; widgets can\'t play video themselves.',
              WidgetShow.both => 'Photos and videos mixed.',
            },
            onChanged: (WidgetShow v) => _set(_c.copyWith(show: v)),
          ),
          _Choices<WidgetSource>(
            heading: 'From',
            value: _c.source,
            labels: const <WidgetSource, String>{
              WidgetSource.all: 'Everything',
              WidgetSource.albums: 'Chosen albums',
              WidgetSource.favourites: 'Favourites',
              WidgetSource.day: 'On this day',
            },
            footer: _c.source == WidgetSource.day
                ? 'Taken on today\'s date in earlier years. On a day with '
                      'none, it shows everything instead.'
                : null,
            onChanged: (WidgetSource v) => _set(_c.copyWith(source: v)),
          ),
          _AlbumPicker(
            albums: albums,
            choosing: _c.source == WidgetSource.albums,
            picked: _c.source == WidgetSource.albums ? _c.albums : _c.leaveOut,
            onChanged: (Set<String> ids) => _set(
              _c.source == WidgetSource.albums
                  ? _c.copyWith(albums: ids)
                  : _c.copyWith(leaveOut: ids),
            ),
          ),
          _Choices<WidgetOrder>(
            heading: 'Order',
            value: _c.order,
            labels: const <WidgetOrder, String>{
              WidgetOrder.shuffle: 'Shuffle, no repeats',
              WidgetOrder.years: 'Spread across years',
              WidgetOrder.newest: 'Newest first',
            },
            footer: switch (_c.order) {
              WidgetOrder.shuffle =>
                'Everything once before anything comes back. A burst of '
                    'shots taken seconds apart counts as one.',
              WidgetOrder.years =>
                'Each change jumps to another year, so old photos come up '
                    'as often as new ones.',
              WidgetOrder.newest => 'Latest first, then back in time.',
            },
            onChanged: (WidgetOrder v) => _set(_c.copyWith(order: v)),
          ),
          _Segments<int>(
            heading: 'Change every',
            value: _c.every,
            labels: const <int, String>{
              10: '10 sec',
              60: '1 min',
              900: '15 min',
              3600: 'Hour',
            },
            footer:
                'The picture changes only while the home screen is on '
                'show, so it costs nothing while the phone is in your pocket.',
            onChanged: (int v) => _set(_c.copyWith(every: v)),
          ),
          _Segments<WidgetFit>(
            heading: 'Fit',
            value: _c.fit,
            labels: const <WidgetFit, String>{
              WidgetFit.whole: 'Whole photo',
              WidgetFit.fill: 'Fill the widget',
            },
            footer: _c.fit == WidgetFit.whole
                ? 'Shows all of each photo, over a blurred copy of itself.'
                : 'Crops each photo to fill the widget edge to edge.',
            onChanged: (WidgetFit v) => _set(_c.copyWith(fit: v)),
          ),
          _Choices<WidgetCaption>(
            heading: 'Caption',
            value: _c.caption,
            labels: const <WidgetCaption, String>{
              WidgetCaption.date: 'Date',
              WidgetCaption.ago: 'How long ago',
              WidgetCaption.album: 'Album name',
              WidgetCaption.none: 'Nothing',
            },
            onChanged: (WidgetCaption v) => _set(_c.copyWith(caption: v)),
          ),
          InsetGroup(
            footer: 'A small arrow in the corner that skips to the next one.',
            children: <Widget>[
              GroupRow(
                title: 'Skip arrow',
                chevron: false,
                trailing: CupertinoSwitch(
                  value: _c.skip,
                  onChanged: (bool v) => _set(_c.copyWith(skip: v)),
                ),
                onTap: () => _set(_c.copyWith(skip: !_c.skip)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A sliding segmented control in its own group, for a short choice.
class _Segments<T extends Object> extends StatelessWidget {
  const _Segments({
    required this.heading,
    required this.value,
    required this.labels,
    required this.onChanged,
    this.footer,
  });

  final String heading;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;
  final String? footer;

  @override
  Widget build(BuildContext context) => InsetGroup(
    header: heading,
    footer: footer,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: CupertinoSlidingSegmentedControl<T>(
          groupValue: value,
          children: <T, Widget>{
            for (final MapEntry<T, String> e in labels.entries)
              e.key: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(e.value, maxLines: 1),
              ),
          },
          onValueChanged: (T? v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    ],
  );
}

/// Rows with a checkmark on the chosen one, iOS's way of picking one of a
/// few longer options.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.heading,
    required this.value,
    required this.labels,
    required this.onChanged,
    this.footer,
  });

  final String heading;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return InsetGroup(
      header: heading,
      footer: footer,
      dividerIndent: AppSpacing.lg,
      children: <Widget>[
        for (final MapEntry<T, String> e in labels.entries)
          Semantics(
            selected: e.key == value,
            inMutuallyExclusiveGroup: true,
            child: GroupRow(
              title: e.value,
              chevron: false,
              trailing: e.key == value
                  ? Icon(CupertinoIcons.checkmark, size: 20, color: cs.primary)
                  : null,
              onTap: () => onChanged(e.key),
            ),
          ),
      ],
    );
  }
}

/// The albums, with a tick on each picked one: which to show when the
/// source is chosen albums, and which to leave out otherwise.
class _AlbumPicker extends StatelessWidget {
  const _AlbumPicker({
    required this.albums,
    required this.choosing,
    required this.picked,
    required this.onChanged,
  });

  final AsyncValue<List<Album>> albums;
  final bool choosing;
  final Set<String> picked;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<Album> list = albums.value ?? const <Album>[];
    return InsetGroup(
      header: choosing ? 'Albums to show' : 'Leave out',
      footer: choosing
          ? (picked.isEmpty ? 'Pick at least one album.' : null)
          : 'These albums never appear, even with Everything or Favourites.',
      dividerIndent: 64,
      children: <Widget>[
        if (albums.isLoading && list.isEmpty)
          const SizedBox(height: 56)
        else if (list.isEmpty)
          const GroupRow(title: 'No albums with photos yet', chevron: false)
        else
          for (final Album a in list)
            Semantics(
              checked: picked.contains(a.id),
              child: GroupRow(
                leading: _Cover(album: a),
                leadingWidth: 40,
                title: a.name,
                subtitle: Fmt.count(a.count, 'item'),
                chevron: false,
                trailing: picked.contains(a.id)
                    ? Icon(
                        choosing
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.minus_circle_fill,
                        size: 22,
                        color: choosing ? cs.primary : cs.error,
                      )
                    : Icon(
                        CupertinoIcons.circle,
                        size: 22,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                onTap: () => onChanged(
                  picked.contains(a.id)
                      ? (Set<String>.of(picked)..remove(a.id))
                      : <String>{...picked, a.id},
                ),
              ),
            ),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.album});
  final Album album;

  @override
  Widget build(BuildContext context) {
    final AssetEntity? cover = album.cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: SizedBox.square(
        dimension: 40,
        child: cover == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
              )
            : Image(
                image: AssetEntityImageProvider(
                  cover,
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(120),
                ),
                fit: BoxFit.cover,
              ),
      ),
    );
  }
}
