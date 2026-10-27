# EasyHealthy

EasyHealthy is a diet and fitness tracking app built with Flutter. It brings meal
logging, recipe discovery, activity tracking, and workout planning into one place,
helping users keep track of their daily habits and progress.

Users can search for foods, record meals and nutrients, discover recipes suited to
their nutrition goals, and build daily meal plans. Fitness features include
activity logs, habit reminders, manual workout planning, and optional AI-assisted
workout generation.

## Features

- **Meal tracking:** Log breakfast, lunch, dinner, and snacks, adjust portions, and
  track calories, protein, carbohydrates, and fat.
- **Food search and custom foods:** Look up nutrition information through USDA
  FoodData Central or create and manage personal food entries in My Foods.
- **Recipe discovery:** Browse recipes by category, view ingredients and
  preparation steps, save favourites, and add recipes to meal logs.
- **Recommendations and meal plans:** Find recipes based on nutrition targets
  and meal history, and generate plans for a selected day.
- **Fitness and habits:** Record activities, create workout plans, track habits,
  and schedule reminders. Gemini-assisted workout generation is available as an
  optional integration.
- **Progress views:** Follow daily, weekly, and monthly trends through charts and
  summaries, with PDF export for progress reports.
- **Account and preferences:** Sign in with Google, manage profile information
  and goals, and switch between light and dark themes.

## Tech Stack

| Area | Technologies |
| --- | --- |
| Development environment | Android Studio |
| Framework and language | Flutter, Dart |
| State management | Provider |
| Authentication | Firebase Authentication, Google Sign-In |
| Database | Cloud Firestore |
| Food and nutrition data | USDA FoodData Central API, `http` |
| AI-assisted workout planning | Gemini API, `google_generative_ai` |
| Charts and progress indicators | `fl_chart`, `percent_indicator` |
| Local notifications and time zones | `flutter_local_notifications`, `flutter_timezone`, `timezone` |
| PDF generation and printing | `pdf`, `printing` |
| UI utilities | `google_fonts`, `cached_network_image`, `shimmer` |

## How It Works

The Flutter interface uses Provider for theme state and Firebase Authentication
for Google sign-in. Cloud Firestore stores user profiles, meal logs, saved
recipes, activities, habits, and workout plans. Food searches use the USDA
FoodData Central API, while recipe browsing and ranking use a bundled JSON
catalogue.

Recipe recommendations combine two signals: how closely a recipe matches the
user's nutrition targets, and how similar its ingredients and categories are to
recipes the user has saved or logged. The combined ranking also supports daily
meal planning. Gemini is used separately to generate workout suggestions from
the user's preferences and available activities.

## Getting Started

### Requirements

- Flutter 3.35.4 / Dart 3.9.2 or a compatible version.
- Android Studio with the Flutter and Dart plugins installed.
- Android SDK and an emulator or physical device.
- A Firebase project with Google sign-in and Cloud Firestore enabled.
- A USDA API key for food search, and an optional Gemini API key for AI workouts.

### Installation

```powershell
git clone https://github.com/jingyaong/easyhealthy.git
cd easyhealthy
flutter pub get
```

### Firebase

Follow the [Firebase for Flutter setup guide](https://firebase.google.com/docs/flutter/setup)
to install the Firebase and FlutterFire CLIs and configure your project:

```powershell
firebase login
flutterfire configure --project=YOUR_FIREBASE_PROJECT_ID
```

This generates the Firebase configuration used by `lib/firebase_options.dart`.
Complete the Android Google sign-in setup, including the signing fingerprint.
Configure Firestore Security Rules to restrict user records to their owners and
create any indexes requested by the application's queries.

The database uses `users/{uid}` and its subcollections, plus `activities`,
`habits`, `user_activities`, `user_habits`, and `workout_plans`. Populate the shared
activity and habit catalogues from the JSON files in `assets/seeds/` using an
administrative process. The Flutter seed utilities in `lib/utils/` use client
permissions and require an appropriately authorized development setup.

### API Configuration

Create your local configuration file:

```powershell
Copy-Item config/development.example.json config/development.local.json
```

Fill in the keys for the integrations you want to use:

| Setting | Used for |
| --- | --- |
| `USDA_API_KEY` | Food search and nutrition lookup |
| `GEMINI_API_KEY` | Optional AI-assisted workout generation |

Key registration: [USDA FoodData Central](https://fdc.nal.usda.gov/api-guide/)
and [Gemini API](https://ai.google.dev/gemini-api/docs/api-key).

### Run in Android Studio

The project was developed using Android Studio. After completing the Firebase
and API configuration above:

1. Open the `easyhealthy` project root in Android Studio, where `pubspec.yaml` is
   located.
2. Open the built-in Terminal and install dependencies:

   ```powershell
   flutter pub get
   ```

3. Start an Android emulator from **Tools > Device Manager**, or connect an
   Android device with USB debugging enabled. Select it in the device selector.
4. Open **Run > Edit Configurations**. Select the Flutter configuration for
   `lib/main.dart`, or create a Flutter configuration with that Dart entrypoint.
5. Set **Additional run args** to:

   ```text
   --dart-define-from-file=config/development.local.json
   ```

6. Apply the configuration and click the green **Run** button to launch the app.

For IDE setup, see the [Flutter Android Studio guide](https://docs.flutter.dev/tools/android-studio).

You can also launch the app from Android Studio's Terminal with the emulator
running or device connected:

```powershell
flutter run --dart-define-from-file=config/development.local.json
```

The local configuration file is ignored by Git. Dart defines are embedded in the
compiled app, so use a backend to protect API credentials in a distributed build.

## Recipe Dataset

The recipe catalogue in `assets/recipes.json` contains **1,021 recipes** from a
dataset obtained through Kaggle. The records reference BBC Good Food recipes and
retain their original author names and source URLs.

Each recipe includes:

- A name, description, ingredients, and preparation steps.
- Nutrition information including calories, protein, carbohydrates, fat, fibre,
  sugars, saturated fat, and salt.
- Categories, difficulty, serving count, preparation and cooking times.
- Ratings, the original recipe URL, and a remotely hosted image URL.

This catalogue powers recipe browsing, favourites, recommendations, and daily
meal planning. Food search uses the USDA FoodData Central API separately. Recipe
photos are loaded from the URLs in the dataset rather than stored in this
repository.

Activity and habit catalogues are available in `assets/seeds/`.

## Code Quality Checks

Run these commands in Android Studio's Terminal to analyze the Dart code and run
the automated tests:

```powershell
flutter analyze
flutter test
```

## My Contributions

EasyHealthy was developed as a two-person university final-year project. My work
focused on:

- Meal tracking, USDA food lookup, and custom food management.
- Recipe discovery, details, and favourites.
- Recommendation logic combining nutrition targets with saved and logged recipe
  history.
- Daily meal-plan generation and nutrition progress views.

I also collaborated on the home and profile sections.
