/// OAuth client ids compiled into the build.
///
/// These are public PKCE clients, so the id is not a secret; it is still kept
/// out of the repository so forks can ship their own registrations:
///
/// ```
/// flutter build windows \
///   --dart-define=GOOGLE_DRIVE_CLIENT_ID=xxx.apps.googleusercontent.com \
///   --dart-define=GOOGLE_DRIVE_CLIENT_SECRET=yyy \
///   --dart-define=DROPBOX_APP_KEY=zzz \
///   --dart-define=ONEDRIVE_CLIENT_ID=www
/// ```
///
/// Android adds one more, because it signs in through the Google SDK instead
/// of the loopback flow:
///
/// ```
/// flutter build apk \
///   --dart-define=GOOGLE_DRIVE_SERVER_CLIENT_ID=uuu.apps.googleusercontent.com
/// ```
///
/// The loopback listener always sends `http://127.0.0.1:<port>` as the
/// redirect URI (never `localhost`). It tries 53682, 53683, 53684 and then a
/// random port, the last only for providers that accept any loopback port.
/// Dropbox matches verbatim, so all three fixed ports must be registered there.
class CloudOAuthConfig {
  const CloudOAuthConfig._();

  /// Google Cloud Console → OAuth client of type "Desktop app".
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_DRIVE_CLIENT_ID',
  );

  /// Required in practice. Google's reference lists `client_secret` as
  /// optional for installed apps, but a "Desktop app" client answers the token
  /// exchange with `400 client_secret is missing` without it, for both the code
  /// and the refresh grant. It is not confidential - it ships inside the binary
  /// - and PKCE is what actually protects the flow.
  static const String googleClientSecret = String.fromEnvironment(
    'GOOGLE_DRIVE_CLIENT_SECRET',
  );

  /// Android signs in through Credential Manager, which authenticates against
  /// the *web* client id of the same project, not the Android client id. The
  /// Android client (package name + SHA-1) still has to exist in the console;
  /// it is matched by signature, so it never appears in the code.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_DRIVE_SERVER_CLIENT_ID',
  );

  /// Dropbox App Console → app key of a scoped app.
  static const String dropboxAppKey = String.fromEnvironment('DROPBOX_APP_KEY');

  /// Entra ID app registration with a "Mobile and desktop applications"
  /// platform.
  static const String microsoftClientId = String.fromEnvironment(
    'ONEDRIVE_CLIENT_ID',
  );
}
