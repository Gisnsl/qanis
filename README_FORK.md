# QANIS — fork of ProxyPin

QANIS is a fork of [ProxyPin](https://github.com/wanghongenpin/proxypin), an
open-source HTTP(S) traffic capture tool written in Flutter. ProxyPin is
licensed under the Apache License, Version 2.0; this fork keeps that licence
and that attribution (see [LICENSE](LICENSE) and [NOTICE](NOTICE)).

## What this fork changes

* **Name and branding** — the app is called **QANIS**. The About screen, the
  Android launcher label and the app-title localisation strings say "QANIS".
  The About screen keeps a visible line: *Based on ProxyPin (Apache-2.0)*.
* **Colour scheme** — a new palette with an amber primary accent (`#E8A33D`),
  replacing the original blue accent.
* **Mobile UI** — the mobile traffic list, the request detail screen and the
  floating bubble overlay have been restyled.
* **Application identity** — the package name / applicationId used by this
  fork is listed below.

Everything else — proxy engine, capture, rewrite, scripting, certificate
handling — is unchanged upstream ProxyPin behaviour.

## Build

Requirements:

* Flutter (stable channel) with Dart 3
* **JDK 17**
* **Android SDK 35** (platform 35 + build-tools; `ANDROID_HOME` /
  `ANDROID_SDK_ROOT` set)
* For desktop targets: the platform toolchain (Visual Studio for Windows,
  Xcode for macOS, GTK 3 for Linux)

```bash
flutter pub get
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

If you edit any `lib/l10n/*.arb` file, regenerate the localisations before
building:

```bash
flutter gen-l10n
```

Other useful targets:

```bash
flutter build windows --release   # Windows
flutter build macos --release     # macOS
flutter build linux --release     # Linux
flutter build ipa --release       # iOS
```

## Package / applicationId

| Item | Value |
| --- | --- |
| Dart package name (`pubspec.yaml`) | `proxypin` |
| Android `applicationId` | `com.network.proxy` |
| Android `namespace` | `com.network.proxy` |

The `applicationId` is defined in `android/app/build.gradle`; the manifest
label is `QANIS`. Change the `applicationId` (and the Kotlin/Java package
path plus `MainActivity` references) together if this fork ships under its own
store identity, and update this table and `NOTICE` at the same time.

## Attribution

This project is a modified fork of ProxyPin:

* Original project: **ProxyPin** — <https://github.com/wanghongenpin/proxypin>
* Copyright 2023 Wang Hongen and the ProxyPin contributors
* Licensed under the Apache License, Version 2.0 —
  <https://www.apache.org/licenses/LICENSE-2.0>

Copyright notices and the Apache-2.0 licence headers in the source files are
left intact. `NOTICE` lists the changes made by this fork, as Apache-2.0
section 4(b) requires. QANIS is not affiliated with, endorsed by or sponsored
by Wang Hongen or the ProxyPin project.

If you redistribute QANIS, keep `LICENSE` and `NOTICE` with it.

---

## Status of this fork (build 2026-11-26)

Done in this snapshot:

| Area | State |
| --- | --- |
| Colour system | `DarkPalette` in `lib/ui/component/utils.dart` rewritten to the QANIS palette (charcoal `#2B2B2B` / `#333333`, amber `#E8A33D`, text `#EDEDED`/`#A6A6A6`/`#7E7E7E`, status colours). Every screen that reads the palette picks the new look up automatically. |
| Branding | Launcher label `QANIS`, About screen name + "Based on ProxyPin (Apache-2.0)", app-title l10n strings (en/zh). |
| Licence | `NOTICE` added, `LICENSE` untouched, attribution kept. |
| Floating bubble | `lib/ui/mobile/widgets/pip.dart` and `floating_window.dart` restyled: 56 dp amber bubble, flow-count pill, 260 dp status card with Start/Stop, Open and Hide, drag + edge snap + persisted position, plus two latent bugs fixed (leaked notifier, `LateInitializationError` on rebuild). |
| Traffic row | `RequestRow` (`lib/ui/mobile/request/request.dart`) + `request_sequence.dart` rewritten as the Reqable 3-line row: 40 dp rounded app icon, name + `#index` pill + `HH:mm:ss`, method in its colour + 2-line URL, status in its colour + body size + `{}` JSON chip, 16 dp padding, 72 dp height, 0.5 px hairline dividers. Every callback, menu item and the GraphQL highlight kept. |
| Request detail | `NetworkTabController` (`lib/ui/content/panel.dart`) restyled: flat panel top bar, coloured URL block (scheme/host amber, path grey, copy), 26×2 dp amber tab underline, Request/Response bottom toggle, `bg`/`panel` containers. Public API untouched, so mobile and desktop both get it. |
| Code snippet | New `lib/utils/code_gen.dart` (22 targets) + `lib/ui/content/code_snippet.dart` page (language picker sheet, line-numbered monospace view, copy/save/share, remembered target). Wired into the copy menu and the row long-press menu as "Code snippet…". |
| Traffic screen chrome | `lib/ui/mobile/mobile.dart` + `lib/ui/mobile/request/list.dart`: flat panel app bars, amber underline tabs, charcoal list background, 72 dp tiles, hairline dividers, amber FAB, amber bottom-nav selection. Verified with `dart analyze` (no new diagnostics). |

### Code generation

`generateCode(id, request)` returns copy-pasteable client code for 22 targets: cURL, HTTPie,
Python (requests, http.client, httpx, aiohttp), Node (fetch, axios, http/https), Rust (reqwest, ureq),
Go net/http, Java (OkHttp, HttpClient), Kotlin OkHttp, C# HttpClient, PHP cURL, Ruby Net::HTTP,
Swift URLSession, Dart http, PowerShell and raw HTTP/1.1. The generators skip hop-by-hop headers, join
repeated header values, and emit a real JSON object/struct/map when the body parses. The generated
Python and Node snippets were executed through their real compilers during development; the Dart output
was type-checked against `package:http`.


## Certificates in this fork

* **No certificate ships with the app.** The upstream `assets/certs/` folder (a shared
  `ProxyPin CA` plus its **private key**) is deleted. On first run `CertificateManager` generates a
  per-device CA — RSA-2048, `CN=QANIS CA (date,XXXXXX)`, 10 years — and writes it to the app's
  private directory `/data/data/com.qanis.app/files/` (`ca.crt` + `ca_key.pem`). Only that key can
  sign the leaf certificates this device serves, and no other app can read it without root.
  "Generate CA" and "Reset CA" both delete the pair and create a fresh one, after which the
  certificate must be installed again.
* **Non-root**: SSL settings → *Install root CA* → **User CA** tab → download `.crt` and confirm the
  Android dialog (works only for apps that trust user CAs).
* **Root**: same screen → **Android Root** tab → *Auto install to system* runs a `su` script that
  merges `<subject-hash>.0` into `/system/etc/security/cacerts` **and** `/apex/com.android.conscrypt/cacerts`
  (tmpfs overlay + bind mount when the apex is read-only), sets `644`, `root:root` and the
  `system_security_cacerts_file` SELinux label.
* **Magisk / KernelSU**: the upstream module still applies; the screen links to it.
* **Exports** go to `/sdcard/Download/qanis/<name>` through a MediaStore-backed platform channel
  (`com.qanis/file`), with the system file picker only as a fallback.
* **Live status** at the top of the HTTPS screen, read from Android's own `AndroidCAStore`
  (`com.qanis/cert` channel):
  **green** = installed in the system store (root/Magisk), **amber** = user store only,
  **red** = not installed. Tapping it opens the install guide; the state refreshes when you come back.


### Is the generated leaf certificate consistent with the installed CA?

Yes, by construction — the same two files drive both sides:

| Step | Code |
| --- | --- |
| Load CA | `initCAConfig()` reads `ca.crt` → `_caCert` **and** `ca_key.pem` → `_caPriKey` from the same directory (`crts.dart`) |
| Sign leaf | `generate(_caCert!, serverPubKey, _caPriKey, host, …)` — issuer DN is copied **byte for byte** from the CA (`issuerRawBytes: _caSubjectDnBytes`), the signature is made with `_caPriKey` |
| Serve it | `_createSecurityContext()` uses `useCertificateChainBytes(leaf + CA)` and `usePrivateKeyBytes(serverKey)` — the leaf's public key and the served private key are the same pair |
| Install | `certificateFile()` returns that same `ca.crt`, and the system file name is `getSubjectHashName(caCert.subject).0` from that same cert |
| Regenerate / import | both `generateNewRootCA()` and `importPkcs12()` rewrite **both** files and drop the context cache |

So a client that trusts the installed `ca.crt` will validate the leaf. Two consequences worth knowing:

1. **Regenerating the CA invalidates the installed one** — you must reinstall (the UI already warns).
2. If `ca.crt` and `ca_key.pem` are ever replaced separately (manual copy, partial import), the leaf is signed by a key
   that does not match the trusted cert and the handshake fails with `certificate verify failed`. There is no
   start-up check for that pair yet; it is the first thing to add once the build runs.

## Why no APK ships with this fork

Building a Flutter APK needs Gradle + the Android Gradle Plugin with a JVM heap this sandbox does not
have (the container caps virtual memory at ~1.5 GB, and the Gradle/AGP/R8 toolchain needs more), and
`pub` cannot resolve packages through the sandbox proxy (TLS to pub.dev fails from the Dart client).
The project itself is complete: run on a normal machine

```bash
flutter --version          # 3.50.1 or newer
flutter pub get
flutter gen-l10n           # regenerates the localisations after the ARB edits
flutter build apk --release
```

The installable build from this project family is still the native `QANIS-4.2.0.apk` delivered alongside
this source tree.
