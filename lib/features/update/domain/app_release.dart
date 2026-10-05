/// A release on GitHub, reduced to what the app needs to offer it.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.tag,
    required this.apkUrl,
    required this.pageUrl,
    this.notes,
    this.whatsNew = const [],
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

  /// The two or three lines worth putting in front of someone who is being
  /// asked to update, in their own language.
  ///
  /// Not the release notes: those are a page with tables and download links,
  /// written for someone standing in front of GitHub. A dialog gets the
  /// short version or nothing -- and when there is nothing worth naming, the
  /// honest line is that bugs were fixed, which is what every app on the
  /// phone says because it is usually true.
  final List<String> whatsNew;
}
