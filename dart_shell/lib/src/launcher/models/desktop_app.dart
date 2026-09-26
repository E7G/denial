class const DesktopApp({
  required final String id,
  required final String name,
  required final String exec,
  required final String desktopPath,
  required final List<String> categories,
  final List<String> keywords = const <String>[],
  final String? icon,
  final String? iconPath,
  final String? startupWmClass,
}) {
  String get searchableText =>
      <String>[id, name, ...categories, ...keywords].join(' ').toLowerCase();
}
