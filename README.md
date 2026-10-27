# EasyHealthy

A Flutter university final-year project combining meal tracking, recipe discovery,
personalized recipe ranking, activity logging, habits, and workout planning.

This repository is a public portfolio snapshot of a project developed by **Ng Jing
Yao and a teammate**. It starts with fresh Git history; that history represents
publication of this snapshot, not sole authorship of the original application.
The original shared development repository remains private.

## Features

- Google sign-in with Firebase Authentication and profile onboarding.
- Meal logs, USDA FoodData Central lookup, and custom food entries.
- Recipe browsing, saved recipes, and generated daily meal plans.
- Recipe ranking combining nutrition-target matching with ingredient/category
  similarity to a user's saved and logged recipes. The source calls the latter
  component collaborative filtering; it is based on the current user's history,
  rather than comparisons across multiple users.
- Activity tracking, habit reminders, manual workout plans, and optional
  Gemini-assisted workout generation.
- Progress charts, PDF export, and light/dark themes.

## Technology

Flutter / Dart, Firebase Authentication, Cloud Firestore, Provider, USDA FoodData
Central, Gemini API, fl_chart, and flutter_local_notifications.

## Public snapshot

- The original API keys and Firebase project configuration are not included.
- `assets/recipes.json` contains 12 original demonstration records. Their nutrition
  values are synthetic test fixtures, not measured values or dietary advice.
- The original third-party recipe dataset and its remote photos are not
  redistributed. Sample recipes intentionally have no images.
- The app requires a Firebase project you control; cloning it does not grant
  access to the original database or user accounts.
- Android is the primary application target. The other generated platform
  folders are included, but their runtime behavior has not been validated.

## Local setup

Use Flutter 3.35.4 / Dart 3.9.2 or a compatible version, Git, and the Android SDK
with an emulator or device. The package requires Dart `^3.9.2`.

```powershell
git clone https://github.com/jingyaong/easyhealthy.git
cd easyhealthy
flutter pub get
```

### Firebase

1. Create a separate Firebase project and enable Google sign-in in Authentication
   and Cloud Firestore. Register your Android signing fingerprint as required for
   Google sign-in.
2. Install the Firebase CLI and FlutterFire CLI, then authenticate to your account.
3. Run `flutterfire configure --project=YOUR_FIREBASE_PROJECT_ID` from this folder.
   This replaces the deliberate setup placeholder in `lib/firebase_options.dart`
   and generates platform configuration for your project. Follow the CLI's native
   configuration steps for the platform you intend to run.
4. Configure Firestore Security Rules and any required indexes before using real
   data. Rules and indexes from the original project were not supplied in this
   snapshot and have not been audited. Keep user data restricted to its owner;
   do not enable unrestricted database access to make a demo work.
5. Populate the shared `activities` and `habits` collections from
   `assets/seeds/activities_seed.json` and `assets/seeds/habits_seed.json` using a
   trusted administrative process. The optional Flutter seed entry points in
   `lib/utils/` use client permissions; do not loosen production rules to run them.

The app also uses `users/{uid}` and its subcollections, plus the top-level
`user_activities`, `user_habits`, and `workout_plans` collections. Database security
must enforce ownership for these records as well as for profile and meal data.

Firebase setup: https://firebase.google.com/docs/flutter/setup

### Optional API integrations

```powershell
Copy-Item config/development.example.json config/development.local.json
```

Add your own `USDA_API_KEY` and, if needed, `GEMINI_API_KEY` to the local file, then:

```powershell
flutter run --dart-define-from-file=config/development.local.json
```

The local configuration file is ignored by Git. Without a USDA key, food search
reports a configuration error; without a Gemini key, AI workout generation does
the same. Neither feature sends a request with a missing key.

**Dart defines are embedded in compiled clients.** They keep keys out of source
control but do not hide them in a distributed app. Route credentialed API calls
through a backend before distributing a production build. Do not commit API keys,
service-account files, signing keys, or personal data.

- USDA access: https://fdc.nal.usda.gov/api-guide/
- Gemini key guidance: https://ai.google.dev/gemini-api/docs/api-key

## Checks

```powershell
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build web
```

Existing analyzer warnings and style suggestions are tracked as cleanup work;
the checks must still report no compile errors. Tests use demonstration data and
do not contact the original Firebase project or external APIs. Compilation does
not establish that authenticated flows or notification permissions work on a
device with a newly configured Firebase project.

Publication checks on 28 October 2026 passed the three focused tests and reported
no analyzer errors. Existing analyzer warnings and style suggestions remain.
The staged public files also passed a Gitleaks scan and a check for the original
service keys. These checks do not constitute an audit of a deployed Firebase
project.

## Collaboration and contributions

The application was developed as a two-person academic project. Ng Jing Yao's
primary contributions included:

- Meal tracking, USDA food lookup, and custom food management.
- Recipe discovery, details, and favourites.
- Recommendation logic combining nutrition targets with saved and logged recipe
  history.
- Daily meal-plan generation and nutrition progress views.

The home and profile sections were developed collaboratively. This summary is
supported by the original development history and his recollection; individual
commits may include shared work. The public snapshot's fresh Git history does
not imply sole authorship of the application.

## Limitations

This is an academic wellness application, not a clinically validated medical
product. Generated workout plans and nutrition estimates are demonstration
features. Authentication, database rules, indexes, notifications, and API access
need configuration and device testing before a real deployment.

No open-source license has been selected for the shared application code.
Third-party packages and platform assets retain their respective licenses.
