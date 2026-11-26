# Parked UI work

`MobileRequestDetail.dart.txt` is a Reqable-styled mobile request/response screen written against
`lib/ui/mobile/request/request.dart`. It parses (verified with `dart format`) but was never compiled,
because this environment cannot run `flutter analyze` or `flutter build`.

To land it properly, prefer restyling the shared detail screen in `lib/ui/content/panel.dart`
(`NetworkTabController`) instead of adding a second implementation — that way the desktop and mobile
paths stay identical and the Favorites entry point keeps working.
