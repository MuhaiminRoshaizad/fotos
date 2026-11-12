import '../../../core/theme/app_tokens.dart';

/// Heights of the viewer's bottom bars: the thumbnail strip and, under it,
/// the action bar. A video's controls sit just above both.
abstract final class ViewerMetrics {
  static const double stripHeight = 56;
  static const double actionButtonHeight = 48;

  /// The action bar's buttons with its padding above and below.
  static const double actionBarHeight = actionButtonHeight + 2 * AppSpacing.sm;

  static const double bottomBars = stripHeight + actionBarHeight;
}
