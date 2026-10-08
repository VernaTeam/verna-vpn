/// The version this build calls itself, in one place.
///
/// It was written out in four screens and compared against nothing. Now that
/// the app checks GitHub for a newer release, the string has to be a value
/// something can compare -- and a second copy that drifts would mean an app
/// that either never offers an update or offers one it already is.
///
/// Kept in step with `version:` in pubspec.yaml by hand. The build number
/// after the `+` is not part of this: it encodes the ABI (see the note in
/// pubspec.yaml) and says nothing about which release a user is on.
const String kAppVersion = '1.0.5';
