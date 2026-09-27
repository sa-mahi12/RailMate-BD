# RailMate BD — source and CI repository

This is the sole code/build repository. Owner's private `RailMate-BD-internal` repository holds planning, requirements, coordination, test evidence and handoffs. Only `main` exists. No pull requests or feature branches. This starter has no app implementation yet: the coordinator must run `bash scripts/create_flutter_skeleton.sh` only after hosted cloud/provider setup is verified. Read `AGENTS.md` before any task.

Stack: Flutter Android, hosted Supabase Postgres/Auth/Storage/Realtime/REST/pg_graphql/Edge Functions, one small embedded HTML page, optional OpenRouter BYOK and tiny TFLite search model. No Docker and no local application DB. All ticket/payment content is educational and simulated. This repository cannot sell real railway tickets.

Commands after scaffold: `flutter pub get`, `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`, `flutter build apk --debug`. CI workflow performs these after an actual Flutter source exists and requires only safe public Supabase app config. A CI job skipped prior to scaffolding is not a successful APK build.
