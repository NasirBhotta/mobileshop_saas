# Mobile Shop Platform Admin

This directory is a transferable Flutter Web foundation. Copy its contents into
a standalone directory, then run `flutter create --platforms web .` once to add
generated web runner files without replacing `lib/`, `test/`, or `pubspec.yaml`.

Run with public Supabase configuration only:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Never provide a service-role key to this application. Platform-admin membership
must be created by a trusted backend or directly through a protected operational
workflow.
