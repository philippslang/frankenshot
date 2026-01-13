# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Frankenshot is a Flutter mobile app for controlling a custom Spinshot tennis ball machine controller.

## Development Commands


```bash
# Get dependencies
flutter pub get

# Run the app (debug mode)
flutter run

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Analyze code for issues
flutter analyze

# Build for Android
flutter build apk
```

## Project Structure

```
frankenshot/          # Flutter project root
├── lib/              # Dart source code
│   └── main.dart     # App entry point
├── test/             # Widget and unit tests
└── pubspec.yaml      # Dependencies and project config
```

## Tech Stack

- Flutter SDK ^3.10.7
- Dart with flutter_lints for static analysis
- Material Design (uses-material-design: true)
