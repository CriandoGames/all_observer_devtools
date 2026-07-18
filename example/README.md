# all_observer_devtools_example

Demo app for the `all_observer_devtools` runtime bridge and extension
panel in this repo. It exercises `Observable`, `Computed`, a reactive
collection, a debounce worker, `ObservableFuture`, and runtime node/scope
creation+disposal via `ReactiveScope` — enough Observer Protocol traffic
for every screen of the extension panel to have something to show.

## First-time setup

This directory only has `pubspec.yaml` and `lib/main.dart` — no platform
folders (`android/`, `windows/`, `web/`, etc.) are checked in, since those
are generated. From inside `example/`, run:

```
flutter create --platforms=windows,web .
```

(swap `windows` for `macos`/`linux`/whatever you actually run on; add more
platforms with a comma-separated list). Modern Flutter detects the
existing `pubspec.yaml`/`lib/` and only adds the missing platform folders
— it will not overwrite your dependencies.

Then:

```
flutter pub get
```

## Running it

```
flutter run -d chrome
```

or `-d windows` / any other connected device. `AllObserverDevTools
.initialize()` runs automatically on startup (debug builds only, gated by
`assert()` — see `lib/main.dart`).

## Watching it from DevTools

1. With the app running, open Flutter DevTools for it (the `flutter run`
   console prints a DevTools URL, or use your IDE's "Open DevTools"
   action).
2. Go to the **Extensions** tab and select **all_observer**. The first
   time, this loads `../extension/devtools/build` — build it first if you
   haven't (see the root `README.md`'s "The extension panel" section).
3. Use the app's five demo sections — Counter, Task list, Search, Profile,
   Dynamic counters — and watch the Nodes/Timeline/Dependencies/Scopes/
   Warnings tabs update live.

What each section is for:

| Section | Exercises |
| --- | --- |
| Counter | Basic `Observable` + `Computed`, a stable dependency edge. |
| Task list | A reactive collection (`ObservableList`) and a derived `Computed` summary. |
| Search | A `debounce` worker driving state on a delay — good for the Timeline tab's ordering. |
| Profile | `ObservableFuture`'s loading/data/error node lifecycle; toggle "Force error" to see an error state. |
| Dynamic counters | The only section that creates *and disposes* nodes/scopes at runtime — "Add counter" emits `ScopeCreated`/`NodeCreated`; "Remove last" emits `NodeDisposed`/`ScopeDisposed`. Everything else in this app lives for the app's whole lifetime, so this is the one to watch for the Nodes screen's "Disposed" filter and the Scopes screen's disposal diagnostics.
