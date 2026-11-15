# ClassWorkPulse

An offline Flutter app (Android and iOS) for teachers and parents to log
multiple students' daily reading progress and ask an on-device AI assistant
about the selected student.

Nothing leaves the device. Entries are stored in a local SQLite database, and
the assistant is a GGUF model run by llama.cpp inside the app. The release
build does not request the internet permission.

## Features

- **Students** - add, switch between, edit, and delete student profiles. Each
  student has separate entries and assistant context.
- **Today** - the daily entry: what the student accomplished, reading ability,
  reading comprehension, and free notes. There is one entry per day; saving a
  day again updates it. Earlier days can be filled in with **Change**.
- **History** - every entry, newest first. Tap to edit, or delete.
- **Assistant** - generate a progress summary or ask questions. Answers are
  written by the local model from the saved entries.

Reading ability and comprehension use one four-step scale: Needs support,
Developing, On track, Excelling.

## Setup

```sh
flutter pub get
dart run tool/fetch_model.dart   # one-time, 808 MB download
flutter run
```

`tool/fetch_model.dart` downloads **Llama 3.2 1B Instruct (Q4_K_M)** into
`assets/models/` and verifies its checksum. The file is ignored by git because
of its size, so run the script after every fresh clone. Building needs an
internet connection once, to fetch the model and the prebuilt llama.cpp
runtime; the built app needs none.

If the app is built without a model, everything except the Assistant tab still
works, and that tab explains what is missing.

To use a different model, put any chat-capable `.gguf` file in `assets/models/`
instead (keep a single `.gguf` there). Its chat template is read from the file.

## How it fits together

| Path | Role |
| --- | --- |
| `lib/data/app_database.dart` | SQLite storage (`sqflite`): student profiles and per-student daily entries |
| `lib/models/daily_entry.dart` | Entry model and the rating scale |
| `lib/screens/` | Onboarding, daily log form, history, assistant chat |
| `lib/ai/model_installer.dart` | Makes the bundled model available as a file |
| `lib/ai/progress_context.dart` | Builds the model's prompt from the saved entries |
| `lib/ai/assistant_controller.dart` | Loads the model (`llamadart`) and runs the chat |
| `android/.../MainActivity.kt` | Streams the model out of the APK on first use |

For each question the app rebuilds the system prompt from the selected
student's database records: an
overview calculated in Dart from every entry (averages, latest rating, trend)
followed by the most recent daily records, as many as fit a fixed token
budget. The model therefore always sees current data, and does not have to do
the arithmetic itself.

## Things to know

- **App size.** The model makes the app roughly 0.9 GB. Android cannot load a
  model from inside the APK, so the first time the Assistant tab is opened the
  model is copied into app storage (about another 0.8 GB, once). iOS loads it
  in place.
- **Store distribution.** Google Play limits the base install to 200 MB, so a
  Play release needs the model moved into an install-time asset pack (Play
  Asset Delivery). Sideloaded APKs and the App Store are not affected.
- **Devices.** 64-bit Android (arm64, plus x86_64 for emulators) and iOS 16.4
  or newer. Allow about 1 GB of free memory for the assistant.
- **Model licence.** Llama 3.2 is distributed under Meta's Llama 3.2 Community
  License, which carries attribution and acceptable-use terms for apps that
  ship it. Review it before distributing the app.
- **Answer quality.** A 1B-parameter model is small. It summarises well from
  the records it is given but can still misstate details, which is why the
  assistant screen points people to the History tab for anything important.

## Tests

```sh
flutter test
```

Covers the database layer, the prompt builder, and the onboarding and
daily-entry flow.
