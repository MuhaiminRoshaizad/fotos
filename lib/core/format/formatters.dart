/// Display formats fixed by the project conventions: dates dd/mm/yyyy, times
/// 24-hour HH:mm, English month and day names.
abstract final class Fmt {
  static const List<String> months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> weekdays = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String date(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  static String time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  static String monthYear(DateTime d) => '${months[d.month - 1]} ${d.year}';

  static String dayHeading(DateTime d) =>
      '${weekdays[d.weekday - 1]}, ${date(d)}';

  /// Video length: m:ss, or h:mm:ss from an hour up.
  static String duration(Duration d) {
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '$m:${_two(s)}';
  }

  /// File size in decimal units, as Android's own Files app shows them.
  static String size(int bytes) {
    if (bytes >= 1000000000) return '${_oneDecimal(bytes / 1000000000)} GB';
    if (bytes >= 1000000) return '${_oneDecimal(bytes / 1000000)} MB';
    if (bytes >= 1000) return '${(bytes / 1000).round()} KB';
    return '$bytes B';
  }

  /// 110.86 reads as 110.9 and 4.0 as 4, like Android's own storage screens.
  static String _oneDecimal(double v) {
    final String s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  static String count(int n, String singular, [String? plural]) =>
      '$n ${n == 1 ? singular : (plural ?? '${singular}s')}';
}
