import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// This public snapshot deliberately contains no original Firebase project setup.
/// Replace this placeholder by running `flutterfire configure` for your own project.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw StateError(
    'Firebase is not configured. Run flutterfire configure for your own '
    'Firebase project before starting EasyHealthy.',
  );
}
