/// "30s ago", "5 min ago", ...
String timeAgo(DateTime? time) {
  if (time == null) return 'no data';

  final diff = DateTime.now().difference(time);
  final seconds = diff.inSeconds;

  if (seconds < 5) return 'just now';
  if (seconds < 60) return '${seconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}
