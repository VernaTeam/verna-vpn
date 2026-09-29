/// A release on GitHub, reduced to what the app needs to offer it.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.tag,
    required this.apkUrl,
    required this.pageUrl,
    this.notes,
  });

  /// Digits only: "1.0.1", never "v1.0.1".
  final String version;

  /// As GitHub spells it, for the log and for anything a person reads.
  final String tag;

  /// The file for this phone's processor, or the release page when the
  /// release carries nothing that matches.
  final String apkUrl;

  final String pageUrl;

  /// The release notes, as written on GitHub. May be empty.
  final String? notes;
}
