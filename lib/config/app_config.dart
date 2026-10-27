/// Developer-supplied values for a local demonstration build.
///
/// Dart defines are embedded in compiled clients; they are not a secret store.
/// A distributed application should call credentialed services through a backend.
abstract final class AppConfig {
  static const usdaApiKey = String.fromEnvironment('USDA_API_KEY');
  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
}
