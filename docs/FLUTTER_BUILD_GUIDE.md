# DocSynapse — Flutter Build Guide

**Audience:** Flutter engineer(s) implementing the DocSynapse doctor app from the static HTML/CSS mockups in this repo.
**Goal:** a single, precise blueprint — design tokens, themes, OS-adaptive behaviour, the full page/widget catalog, the **event-driven + API-integrated architecture** (§3.5), the data model, and the key flows — so implementation is mechanical, not guesswork.

**Architecture in one line:** **MVVM-C** with GetX (View = `GetView`, ViewModel = `GetxController`, Model = Repository) · REST via dio · **real-time (WebSocket/SSE) + FCM push feeding a typed EventBus** · `GetStorage`/Hive as offline cache. See §3.5.
**North star:** *feel more polished than a native app on both platforms* — one codebase, Material 3 foundations, Cupertino behaviours where iOS users expect them, and a signature motion/spacing language applied everywhere.

> The mockups are the source of truth for visuals. This document translates them into a Flutter architecture. Every token below is lifted from [`global.css`](../global.css); every page from the repo's HTML files.

---

## 1. Product overview

DocSynapse ("Mysaa Life Health Care · for verified physicians") is a doctor-facing network + CME + referral + medico-legal app. It runs as a 390×844 phone frame in the mockups. Core pillars:

| Module | Pages |
|---|---|
| **Auth / onboarding** | `login` (login + 4-step register wizard + reset-password flow) |
| **Home** | `home`, `notifications` |
| **Network & Posts** | `network`, `post`, `post-case`, `case-discussions`, `create-group`, `group`, `explore`, `specialties` |
| **CME / Conferences** | `cme`, `cme-details`, `cme-sessions`, `cme-video`, `create-cme`, `my-programs`, `mylearning`, `saved-cmes`, `speakers` |
| **Referral** *(owned module)* | `referral`, `create-referral` |
| **Medico-Legal** *(owned module)* | `medicolegal`, `accreditation-requests`, `create-accreditation-request` |
| **Doxy (AI assistant)** | `doxy` |
| **Profile & Settings** | `profile`, `clinical-profile`, `hospital-affiliations`, `credentials`, `credential-add`, `settings`, `devices`, `files`, `presentations` |
| **Reference** | `typography`, `index` |

38 screens total. Bottom-nav destinations: **Home · Post · Doxy(raised) · CME · Refer**.

---

## 2. Recommended stack

| Concern | Choice | Why |
|---|---|---|
| Flutter | 3.24+ / Dart 3.5+ | Material 3 mature, `ThemeExtension`, predictive back |
| **State + DI + routing** | **GetX** (`get`) | one package covers reactive state (`.obs` / `Obx`), dependency injection (`Get.put` / `Get.lazyPut` / `Get.find`), named routes with per-route transitions & **bindings**, plus `Get.snackbar` / `Get.dialog` / `Get.bottomSheet` |
| Local storage | **GetStorage** (`get_storage`) — Hive for large/complex data | `GetStorage` is a synchronous key/value store that maps **1:1** to the mockup's `localStorage` keys; use Hive only for big list entities |
| Models | **freezed** + **json_serializable** | immutable entities, `copyWith` |
| Network (REST) | **dio** + interceptors | OTP/register/NMC lookup, feeds, auth + refresh tokens |
| Real-time | **web_socket_channel** (or SSE) | live CME counts, referral/notification push, Doxy streaming |
| Push | **firebase_messaging** | background/terminated notifications + deep links |
| Events | broadcast `Stream` / **event_bus** | decoupled cross-feature domain events (§3.5) |
| Icons | **flutter_svg** | the mockups are 100% inline SVG — reuse the exact paths |
| Fonts | **google_fonts** *or* bundled Inter | design uses Inter 400/500/600/700 only |
| Haptics | `HapticFeedback` (built-in) | tactile press feedback (see §6) |
| Connectivity | **connectivity_plus** | online/offline `RxBool`, offline banner, sync queue (§14.4) |
| Secure storage | **flutter_secure_storage** | tokens + PII in Keychain/Keystore (§14.3) |
| Loaders | **skeletonizer** (or `shimmer`) | shape-matching skeletons (§14.2) |
| Security (opt.) | **local_auth**, **flutter_jailbreak_detection** | biometric app-lock, root/jailbreak detection (§14.3) |
| Misc | `flutter_animate` (optional), `pinput` (OTP), `image_picker` (photo), `cached_network_image` | speed up polish |

Use **`GetMaterialApp`** as the root so GetX owns navigation, theming (`Get.changeThemeMode` / `Get.changeTheme`), and overlays. Keep the dependency list lean — the design language is simple enough to hand-build most widgets, which gives pixel control the packages won't.

> **GetX conventions used throughout this doc:** every screen is a `GetView<XController>`; state is exposed as `.obs` fields read inside `Obx(...)`; controllers are provided by a **`Binding`** attached to the route (lazy-loaded, auto-disposed); cross-feature singletons (`ThemeController`, `SessionController`) are `Get.put(..., permanent: true)` in an `InitialBinding`.

---

## 3. Project structure

```
lib/
  main.dart
  app.dart                      # MaterialApp.router + theme wiring
  bindings/
    initial_binding.dart        # Get.put ThemeController + SessionController (permanent)
  core/
    theme/
      app_colors.dart           # ColorTokens ThemeExtension (see §4)
      app_typography.dart       # TextTheme + text roles
      app_spacing.dart          # spacing / radii / shadows / durations
      app_theme.dart            # builds ThemeData per brand + brightness
      theme_controller.dart     # GetxController: current brand + brightness, persisted
    platform/
      adaptive.dart             # iOS/Android transitions, physics, haptics
    widgets/                    # shared widget catalog (see §8)
      soft_card.dart
      pill_button.dart
      primary_button.dart
      app_top_bar.dart
      app_bottom_nav.dart
      app_bottom_sheet.dart
      app_toast.dart
      otp_input.dart
      labeled_field.dart
      chip_row.dart
      section_header.dart
      rise_in.dart              # the "rise" entrance animation
  data/
    models/                     # freezed entities (see §10)
    repositories/               # storage-backed repos
    local/hive_boxes.dart
  features/
    auth/          # each feature: view/ + controller/ + binding/
      view/login_screen.dart
      controller/auth_controller.dart
      binding/auth_binding.dart
    home/ network/ cme/ referral/ medicolegal/ doxy/ profile/ settings/
  routing/
    app_pages.dart              # List<GetPage> (route + page + binding + transition)
    app_routes.dart             # route-name constants
```

One folder per module = clean mapping to the page table in §1 and to the two owned modules (Referral, Medico-Legal). Each feature follows the **GetX view/controller/binding** triad: the `binding` `Get.lazyPut`s the controller, the `GetPage` references the binding so the controller is created on navigation and disposed on pop.

---

## 3.5 Architecture — event-driven & API-integrated

The app is **event-driven with a REST + real-time backend**. Nothing is stored only on-device; every mockup `localStorage` write becomes an **API call**, and every server-side change arrives as an **event** the UI reacts to. GetX's reactivity (`.obs` + `Obx`) is the local half; an **EventBus + real-time transport** is the cross-feature/server half.

### Pattern: MVVM (reactive, GetX flavour)

This is **MVVM**, not MVC. The GetX `Controller` is the **ViewModel** — it owns `.obs` state and commands, and the `View` binds to it reactively through `Obx` (two-way reactive binding = the MVVM signature). The `View` never touches the `Model`; the `Model` is the Repository + `freezed` entities/DTOs behind `ApiClient` / `RealtimeService` / `LocalCache`. Bindings (DI) + `AppPages`/middleware add the coordinator layer, so precisely it's **MVVM-C**.

| MVVM role | Layer here |
|---|---|
| **View** | `GetView<XController>` screen — dumb, renders `Obx(...)`, emits intents |
| **ViewModel** | `XController extends GetxController` — `.obs` state, `Status`, commands; no Flutter widgets |
| **Model** | Repository + `freezed` entities/DTOs + `ApiClient` / `RealtimeService` / `LocalCache` |
| **Coordinator (-C)** | `Binding` (DI wiring) + `AppPages`/`GetMiddleware` (routing/guards) |

Rule of thumb: **no `BuildContext` in the ViewModel, no business logic in the View, no widgets in the Model.**

### Layers (unidirectional, event-in / command-out)

```
 View (GetView)                 – dumb; renders Obx(state), sends user intents
   │  intent (method call)            ▲ rebuild on .obs change
   ▼                                  │
 Controller (GetxController)    – holds Rx state + status; orchestrates
   │  command                         ▲ domain event (EventBus) / stream
   ▼                                  │
 Repository                     – maps DTO⇄model; read-through cache; emits events
   │                ┌───────────────────────────────┐
   ▼                ▼                               ▼
 ApiClient (dio)   RealtimeService (WS/SSE)     LocalCache (GetStorage/Hive)
   REST req/resp    server push → events          offline mirror
```

### API integration

- **Client:** `dio` wrapped in an `ApiClient` service (`Get.put(permanent:true)`). Interceptors: **auth** (inject bearer from `SessionService`), **refresh** (queue on `401`, refresh token, replay), **logging**, **error → `AppException`** mapping.
- **Repositories** expose `Future<Model>` for commands/queries and (where live) `Stream<Model>` fed by the realtime layer. DTOs are `freezed`+`json_serializable`, mapped to domain models.
- **Controller status pattern** — every screen models load/empty/error, driven by `Obx`:
  ```dart
  enum Status { idle, loading, success, empty, error }
  class CmeController extends GetxController {
    final status = Status.idle.obs;
    final items  = <CmeProgram>[].obs;
    final CmeRepository repo;
    Future<void> load() async {
      status.value = Status.loading;
      try {
        final r = await repo.fetchHome();          // dio GET
        items.assignAll(r);
        status.value = r.isEmpty ? Status.empty : Status.success;
      } on AppException catch (e) {
        status.value = Status.error; AppToast.error(e.message);
      }
    }
    @override void onInit(){ super.onInit(); load(); }
  }
  ```
- **Optimistic + offline:** write to cache + UI immediately, fire the API, reconcile/rollback on failure; on cold start render cache, then refresh. `GetStorage` holds the `doc*` scalars; Hive holds list entities.

### Event system

A lightweight typed **EventBus** (a broadcast `Stream<AppEvent>`, or the `event_bus` pkg) that any controller can publish to / subscribe from — decoupling features (e.g. accepting a referral updates Home badges, Notifications, and Profile stats without direct calls).

```dart
sealed class AppEvent {}
class AuthChanged        extends AppEvent { final bool signedIn; AuthChanged(this.signedIn); }
class NotificationReceived extends AppEvent { final AppNotification n; NotificationReceived(this.n); }
class ReferralStatusChanged extends AppEvent { final String id; final ReferralStatus s; ReferralStatusChanged(this.id,this.s); }
class CmeLiveUpdated     extends AppEvent { final String id; final int watching; CmeLiveUpdated(this.id,this.watching); }
class RegistrationVerified extends AppEvent {}
class ProfileUpdated     extends AppEvent { final DoctorProfile p; ProfileUpdated(this.p); }

class Bus extends GetxService {
  final _c = StreamController<AppEvent>.broadcast();
  Stream<T> on<T extends AppEvent>() => _c.stream.where((e) => e is T).cast<T>();
  void emit(AppEvent e) => _c.add(e);
}
// subscribe in a controller:
@override void onInit(){ super.onInit();
  Get.find<Bus>().on<ReferralStatusChanged>().listen(_applyStatus); }
```

**Transports that feed the bus**
- **Real-time (WebSocket / SSE):** a `RealtimeService` (permanent) holds the socket, decodes server frames → `bus.emit(...)`. Powers: live CME watcher counts, referral acceptance, Doxy chat streaming, in-app notifications, presence/availability.
- **Push (FCM):** `firebase_messaging` for background/terminated delivery; foreground messages → `NotificationReceived`; tap → deep-link route (`Get.toNamed`).
- **GetX Workers** turn Rx changes into events/side-effects: `debounce(searchQuery, …)` → search API; `ever(session.token, …)` → (re)connect socket; `ever(session.signedIn, …)` → route to login/home; `interval(...)` for polling fallbacks.

### Flow → API + event mapping

| User/system action | API call | Event emitted → who reacts |
|---|---|---|
| Send OTP (register/reset/change) | `POST /auth/otp` | — (awaited) |
| Verify OTP | `POST /auth/otp/verify` | `RegistrationVerified` / auth token set |
| NMC prefill lookup | `GET /register/lookup?regNo&council` | — |
| Create account / login | `POST /auth/register` · `/auth/login` | `AuthChanged(true)` → root routing, socket connect |
| Save workplace/profile edit | `PATCH /me` | `ProfileUpdated` → Home header, Profile |
| Flag registration mismatch | `POST /me/registration/deviation` | daily-reminder scheduler (SessionService) |
| Referral create / cancel / change | `POST/PATCH /referrals` | `ReferralStatusChanged` → Home, Notifications, Profile stats |
| Referral accepted (by peer) | *server push* | `ReferralStatusChanged` (real-time) |
| Save/bookmark CME | `PUT /me/saved-cmes/{id}` | list refresh (optimistic) |
| Live CME watcher tick | *server push* | `CmeLiveUpdated` → CME live card |
| New notification | *push / WS* | `NotificationReceived` → bell badge, list |
| Change phone/email (verified) | `PATCH /me/contact` | `ProfileUpdated` |

> **Auth guard:** a `GetMiddleware` (redirect) on protected `GetPage`s checks `SessionService.signedIn`; `AuthChanged` events flip it and re-route. This replaces the mock `docAuth` check.

---

## 4. Design tokens → Dart

All values are taken verbatim from [`global.css`](../global.css). Encode them as a `ThemeExtension` so any widget reads `Theme.of(context).extension<AppColors>()!`.

### 4.1 Colour tokens (semantic)

Each theme overrides the same token set. Names below match the CSS variables so cross-referencing the mockups is trivial.

| Token | Meaning | Classic (default) | Ocean *(runtime default)* | Forest | White | Colour |
|---|---|---|---|---|---|---|
| `brand` | primary accent | `#7d2c3b` | `#1e5fbf` | `#0f7a5a` | `#111114` | `#2f6fed` |
| `brandDark` | pressed/hover | `#5e2029` | `#164a99` | `#0b5c44` | `#000000` | `#1f57c8` |
| `brandSoft` | tint bg (chips, badges) | `#f4e7e9` | `#e7effc` | `#e2f5ee` | `#f1f2f6` | `#e9f1fe` |
| `gold` | premium/verified accent | `#b0894f` | `#b0894f` | `#b08631` | `#a97e3f` | `#b0894f` |
| `ink` | primary text | `#2a2320` | `#0f2438` | `#12271f` | `#111114` | `#14141a` |
| `slate700` | secondary text | `#514842` | `#31465e` | `#33473f` | `#3a3a42` | `#3a3a44` |
| `muted` | tertiary text | `#71665d` | `#546a80` | `#6f867d` | `#7a7a86` | `#78788a` |
| `line` | hairline border | `#e7e0d4` | `#e1e9f3` | `#dbe9e2` | `#e6e7ee` | `#e6e7ee` |
| `chip` | neutral fill | `#f4f0e8` | `#eef4fb` | `#eef6f2` | `#f2f3f7` | `#eef3fb` |
| `green` | success | `#3f7d4e` | `#1f9d6b` | `#0f7a5a` | `#1f9d6b` | `#1f9d6b` |
| `surface` | app background | `#faf6ee` | `#ffffff` | `#f6fbf8` | `#ffffff` | `#ffffff` |
| `card` | card background | `#ffffff` | `#ffffff` | `#ffffff` | `#ffffff` | `#ffffff` |
| `soft1` | soft card tint | `#f7ede1` | `#e9f1ff` | `#e6f5ee` | `#ffffff` | `#ffffff` |
| `soft2` | alt soft tint | `#f4e7e9` | `#eaf3ff` | `#e9f5e6` | `#ffffff` | `#ffffff` |
| `g1`,`g2` | header gradient | `#9c4453`,`#7d2c3b` | `#4f8be8`,`#1e5fbf` | `#2aa578`,`#0f7a5a` | `#2b2b33`,`#111114` | `#4f8be8`,`#2f6fed` |
| `d1`,`d2`,`d3` | dark hero gradient | `#2b191c`,`#5e2029`,`#7d2c3b` | `#0b2545`,`#123a72`,`#1e5fbf` | `#0a2b20`,`#0e5540`,`#0f7a5a` | `#151519`,`#232329`,`#111114` | `#0b2545`,`#123a72`,`#2f6fed` |
| `red` / `redSoft` | error | `#c0403a` / `rgba(200,64,58,.13)` | (shared) | | | |
| `amber` / `amberSoft` | warning | `#b26a00` / `rgba(212,138,20,.15)` | (shared) | | | |

Extra fixed accents used inline in pages: live-red `#e06a6a`/`#c0464a`, "International Faculty" gold via `color-mix(gold, …)`, mismatch amber `#d64545` (error text).

> **Runtime default theme is Ocean (`blue`)** — the mockups persist `cmeTheme` and fall back to `'blue'`. Set that as the initial brand.

**Colour theme (`whitec`) has multi-colour module icons on Home** (index 1→6): `#2f6fed / #e07b28 / #12a150 / #7c5cff / #e04a8a / #0ea5a5`, each on a matching soft tint. Encode as a per-tile palette used only in that brand.

```dart
// core/theme/app_colors.dart
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color brand, brandDark, brandSoft, gold, ink, slate700, muted, line,
      chip, green, surface, card, soft1, soft2, red, redSoft, amber, amberSoft;
  final List<Color> headerGradient;   // [g1, g2]
  final List<Color> heroGradient;     // [d1, d2, d3]

  const AppColors({ required this.brand, required this.brandDark, /* … */ });

  @override AppColors copyWith({Color? brand, /* … */}) => AppColors(/* … */);
  @override AppColors lerp(ThemeExtension<AppColors>? o, double t) { /* Color.lerp each */ }

  static const ocean = AppColors(
    brand: Color(0xFF1E5FBF), brandDark: Color(0xFF164A99),
    brandSoft: Color(0xFFE7EFFC), gold: Color(0xFFB0894F),
    ink: Color(0xFF0F2438), slate700: Color(0xFF31465E), muted: Color(0xFF546A80),
    line: Color(0xFFE1E9F3), chip: Color(0xFFEEF4FB), green: Color(0xFF1F9D6B),
    surface: Color(0xFFFFFFFF), card: Color(0xFFFFFFFF),
    soft1: Color(0xFFE9F1FF), soft2: Color(0xFFEAF3FF),
    red: Color(0xFFC0403A), redSoft: Color(0x21C8403A),
    amber: Color(0xFFB26A00), amberSoft: Color(0x26D48A14),
    headerGradient: [Color(0xFF4F8BE8), Color(0xFF1E5FBF)],
    heroGradient: [Color(0xFF0B2545), Color(0xFF123A72), Color(0xFF1E5FBF)],
  );
  // classic, forest, white, colour → same shape, values from the table above.
}
```

### 4.2 Typography

Font: **Inter**, weights 400/500/600/700 only. Type scale (from the CSS `--fs-*` / `--font-size-*` tokens, tuned to the 390 px frame):

| Role | Size | Weight | Line-height | Letter-spacing |
|---|---|---|---|---|
| Page title (h1) | 22 | 700 | 1.2 | -0.02em |
| Section title (h2) | 19 | 700 | 1.2 | -0.02em |
| Dialog/sheet title (h3) | 17 | 600 | 1.35 | -0.01em |
| Card title | 15 | 600 | 1.25 | — |
| Body large | 15 | 400 | 1.55 | — |
| Body | 14 | 400 | 1.55 | — |
| Body small | 13 | 400 | 1.35 | — |
| Label / form label | 12 | 500 | — | — |
| Button | 14 | 600 | — | — |
| Input | 15 | 400 | — | — |
| Caption / helper | 11 | 400 | 1.35 | — |
| Nav | 11 | 500 | — | — |
| Caps (eyebrows/badges) | inherit | 700 | — | 0.08em, UPPERCASE |

Fine-grained scale also present: `xs 10.5 / sm 12 / md 13.5 / lg 15 / xl 17 / 2xl 19 / 3xl 22`.
Small-phone (<360 logical px) easing: h1→20, h2→18, 3xl→21, 2xl→18.

```dart
// core/theme/app_typography.dart — build a TextTheme, then expose named roles.
TextTheme buildTextTheme(Color ink, Color muted) {
  TextStyle s(double px, FontWeight w, {double h = 1.5, double ls = 0, Color? c}) =>
      GoogleFonts.inter(fontSize: px, fontWeight: w, height: h, letterSpacing: ls, color: c ?? ink);
  return TextTheme(
    displaySmall:  s(22, FontWeight.w700, h: 1.2,  ls: -0.44), // page title
    headlineSmall: s(19, FontWeight.w700, h: 1.2,  ls: -0.38), // section title
    titleLarge:    s(17, FontWeight.w600, h: 1.35, ls: -0.17), // dialog title
    titleMedium:   s(15, FontWeight.w600, h: 1.25),            // card title
    bodyLarge:     s(15, FontWeight.w400, h: 1.55),
    bodyMedium:    s(14, FontWeight.w400, h: 1.55),
    bodySmall:     s(13, FontWeight.w400, h: 1.35),
    labelLarge:    s(14, FontWeight.w600),                     // button
    labelMedium:   s(12, FontWeight.w500),                     // label
    labelSmall:    s(11, FontWeight.w400, h: 1.35, c: muted),  // caption/nav
  );
}
```

> Convert `em` letter-spacing to logical px: `px = em × fontSize` (e.g. -0.02em @ 22px ≈ -0.44).

### 4.3 Spacing, radii, elevation, motion

```dart
// core/theme/app_spacing.dart
class AppSpacing {
  static const pageH = 20.0;         // .scroll horizontal padding (18–20)
  static const sectionGap = 11.0;    // between section header + content (6–14 range)
  static const hairlineGap = 6.0;    // tight "hairline" inter-element gaps
  static const cardPad = 14.0;       // 12–16
  static const cardGap = 8.0;        // list gaps (7–9)
}
class AppRadii {
  static const card = 16.0;          // 14–18
  static const cardLg = 18.0;
  static const pill = 20.0;          // chips, badges, ptags
  static const button = 13.0;        // 12–14
  static const input = 12.0;
  static const sheetTop = 22.0;      // top corners of bottom sheets
  static const iconChip = 11.0;      // 10–12 (icon tiles)
  static const backBtn = 12.0;
}
class AppShadows {
  static const card = [BoxShadow(color: Color(0x0F101828), blurRadius: 2, offset: Offset(0,1))];
  static const sheet = [BoxShadow(color: Color(0x66000000), blurRadius: 40, spreadRadius: -12, offset: Offset(0,-12))];
  static List<BoxShadow> brandGlow(Color brand) =>
      [BoxShadow(color: brand.withOpacity(.5), blurRadius: 22, spreadRadius: -10, offset: const Offset(0,10))];
}
class AppMotion {
  // the app's signature easing (cubic-bezier(.22,1,.36,1)) — an "emphasized decelerate"
  static const easing = Cubic(0.22, 1, 0.36, 1);
  static const fast = Duration(milliseconds: 160);   // press feedback
  static const base = Duration(milliseconds: 180);   // hover/border transitions
  static const rise = Duration(milliseconds: 500);   // entrance
  static const sheet = Duration(milliseconds: 420);  // sheet slide
}
```

Signature interactions to reproduce everywhere:
- **Press:** `scale(0.9–0.98)` over 160 ms — wrap tappables in a `_PressScale` widget.
- **Entrance:** `.rise` = fade + translateY(12→0) over 500 ms `easing`, staggered per list item (~55–60 ms apart).
- **Border focus/hover:** border colour → `brand` over 180 ms.

---

## 5. Theme system

### 5.1 Five brand themes + light/dark

Brands = `{classic, ocean, forest, white, colour}` (CSS `classical / blue / green / white / whitec`). Persist selection under key **`cmeTheme`** (values: `classical|blue|green|white|whitec`). Default `blue`.

```dart
enum AppBrand { classic, ocean, forest, white, colour }
// persisted strings: classical | blue | green | white | whitec  (key: cmeTheme)

class ThemeController extends GetxController {
  final _box = GetStorage();
  final brand = AppBrand.ocean.obs;      // runtime default = Ocean
  final mode  = ThemeMode.system.obs;

  @override void onInit() {
    super.onInit();
    brand.value = _brandFromId(_box.read('cmeTheme') ?? 'blue');
  }

  void setBrand(AppBrand b) {
    brand.value = b;
    _box.write('cmeTheme', _idFor(b));
    Get.changeTheme(buildTheme(b, Get.isDarkMode ? Brightness.dark : Brightness.light));
  }
  void setMode(ThemeMode m) { mode.value = m; Get.changeThemeMode(m); }
}
```

Wire it once in `GetMaterialApp` (rebuild on brand change with `Obx`):

```dart
final theme = Get.find<ThemeController>();
Obx(() => GetMaterialApp(
  theme:      buildTheme(theme.brand.value, Brightness.light),
  darkTheme:  buildTheme(theme.brand.value, Brightness.dark),
  themeMode:  theme.mode.value,
  initialBinding: InitialBinding(),   // Get.put(ThemeController(), permanent: true), SessionController…
  getPages:   AppPages.pages,
  initialRoute: AppRoutes.login,
));
```

Build one `ThemeData` per (brand, brightness). Wire the `AppColors` extension + `TextTheme` + shaped components:

```dart
ThemeData buildTheme(AppBrand brand, Brightness b) {
  final c = colorsFor(brand, b);                         // AppColors for brand (+ dark variants)
  final scheme = ColorScheme.fromSeed(seedColor: c.brand, brightness: b).copyWith(
    primary: c.brand, surface: c.surface, onSurface: c.ink, error: c.red, outline: c.line,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.surface,
    textTheme: buildTextTheme(c.ink, c.muted),
    extensions: [c],
    splashFactory: NoSplash.splashFactory,               // we use scale-press, not ripple
    cardTheme: CardTheme(color: c.card, elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: c.line))),               // hairline border in every theme
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: c.brand, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.button)),
      textStyle: buildTextTheme(c.ink, c.muted).labelLarge)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: c.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.input),
        borderSide: BorderSide(color: c.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.input),
        borderSide: BorderSide(color: c.brand)),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheetTop)))),
  );
}
```

**Hairline-border rule:** in the mockups every soft card carries a `line` border in all themes so white themes don't lose definition. Bake it into `CardTheme` (above) and any custom `SoftCard`.

**Dark mode:** the mockups are light-only (`color-scheme: light`), but Flutter should ship dark variants. Derive dark tokens per brand (darken `surface`→near-black, raise `card` one step, invert `ink`/`muted`). Because everything reads the `AppColors` extension, adding dark is a data change, not a widget change. Respect `ThemeMode.system` and expose an override in Settings → Appearance.

Switching themes is instant and animated: `AnimatedTheme` (built into `MaterialApp`) + `AppColors.lerp` gives a smooth cross-fade.

### 5.2 Appearance picker

Settings and Profile both open an **Appearance** bottom sheet with a 3-column grid of theme swatches (Classic burgundy, Ocean blue, Forest green, White, Colour gradient). Selecting persists `cmeTheme` and calls the `ThemeController`. Reuse the same widget in both places.

---

## 6. OS-adaptive strategy (the "better than native" layer)

The mockups already branch on OS: they set `data-os = ios | android | other` from the user-agent and use `env(safe-area-inset-*)`. Flutter gets this for free and we go further — **Material 3 look, platform-correct feel.**

| Behaviour | iOS | Android | Flutter implementation |
|---|---|---|---|
| Page transition | slide-from-right + interactive back-swipe | fade-through / shared-axis | per-`GetPage` `transition:` — `Transition.cupertino` on iOS, `Transition.fadeIn`/`native` on Android (or set `GetMaterialApp.defaultTransition`) |
| Predictive back | edge swipe | system predictive-back (Android 14+) | enable `MaterialApp` predictive back; keep pop scopes shallow |
| Scroll physics | rubber-band bounce | glow/stretch | `ScrollConfiguration` → `BouncingScrollPhysics` on iOS, `ClampingScrollPhysics`+stretch on Android; or `AlwaysScrollable…` with platform default |
| Status bar | dark icons on light | dark icons on light | `SystemUiOverlayStyle` per screen via `AnnotatedRegion`; hide the mock status bar entirely (real OS bar shows) |
| Safe areas | notch/home indicator | gesture nav inset | wrap shells in `SafeArea`; bottom nav uses `MediaQuery.padding.bottom` (mirrors `env(safe-area-inset-bottom)`, mock uses `max(22px, inset)`) |
| Haptics | crisp | coarser | `HapticFeedback.selectionClick()` on tab/nav taps, `.lightImpact()` on primary actions, `.mediumImpact()` on success toasts |
| Fonts | Inter (bundled) both platforms for brand consistency | same | bundle Inter so typography is identical cross-platform |
| Switches / pickers | Cupertino switch, wheel pickers | Material | `Switch.adaptive`, `showCupertinoModalPopup` for iOS wheel where a native picker is expected (e.g. council select) |
| Dialogs | Cupertino alert | Material dialog | `showAdaptiveDialog` / `AlertDialog.adaptive` |
| Sheets | rounded modal, drag-to-dismiss | same | `showModalBottomSheet(isScrollControlled, showDragHandle)` — matches the mock `.grab` handle |

```dart
// core/platform/adaptive.dart
bool get isIOS => GetPlatform.isIOS;   // GetX platform helper

// Per-route transition — use in GetPage(transition: adaptiveTransition)
Transition get adaptiveTransition => isIOS ? Transition.cupertino : Transition.fadeIn;

// Give GetMaterialApp this scroll behaviour for platform-correct physics
class AppScrollBehavior extends MaterialScrollBehavior {
  @override ScrollPhysics getScrollPhysics(BuildContext c) =>
      isIOS ? const BouncingScrollPhysics() : const ClampingScrollPhysics();
}

// Example route
GetPage(name: AppRoutes.speakers, page: () => const SpeakersScreen(),
        binding: SpeakersBinding(), transition: adaptiveTransition);
```

**Why it can beat native:** one team ships identical, brand-perfect visuals on both OSes, *plus* the platform-expected gestures/physics/haptics — most native apps only nail one platform. The signature motion (scale-press, staggered rise, animated theme lerp) is applied globally and consistently, which hand-built native screens rarely achieve.

---

## 7. Widget mapping (HTML/CSS → Flutter)

| Mockup element (class) | Flutter |
|---|---|
| `.phone` frame | `Scaffold` (only for the frame in mockups; real app = full screen) |
| `.topbar` + back `.back`/`.bk` | `AppTopBar` (custom) — 40×40 rounded-square back button + ellipsised title |
| `.nav` bottom nav (5 items, raised Doxy) | `AppBottomNav` in `RootScreen` + `IndexedStack` (see §9) |
| `.scroll` | `CustomScrollView` / `ListView` with `AppSpacing.pageH` padding |
| `.card`, `.soft*` cards | `SoftCard` — `Container(color: card/soft1, border: line, radius: 16)` |
| `.chip`, `.chips` row | `ChipRow` → horizontal `ListView` of `Pill` (icon + label) |
| `.ptag` / badges / `.reg-badge` / `.intl-badge` / `.daystag` | `Badge`/`Pill` variants (filled soft + coloured text) |
| `.btn.btn-primary` | `PrimaryButton` (FilledButton, 50 h, brand, glow shadow) |
| `.btn-alt`, `.pv-btn.ghost` | `GhostButton` (outlined, brand text) |
| `.sheet` + `.backdrop` + `.grab` | `showAppSheet()` → `showModalBottomSheet(isScrollControlled, showDragHandle)` |
| `.toast` | `AppToast` overlay (bottom, dark pill, auto-dismiss 1.4 s) |
| `.field` label+input, `.pw-eye` | `LabeledField` / `LabeledTextField` with suffix eye toggle |
| `.otp-row` 6 boxes | `OtpInput` (custom or `pinput`) — auto-advance, paste, backspace nav |
| `.field select` (council) | `AdaptiveDropdown` — Material menu / Cupertino wheel |
| `.ring` progress (CME credits) | `CircularProgressIndicator` custom-painted or `CustomPaint` |
| `.timeline` / `.tl-item` (agenda) | `Column` of `TimelineTile` (rail + dot + card) |
| `.modules` grid (home) | `GridView` 3-col, `childAspectRatio` for uniform tiles |
| `.rise` entrance | `RiseIn` wrapper (`AnimationController` fade+slide) |
| press `scale(.9)` | `PressScale` wrapper on all tappables |
| avatar stacks (`.live-avs`) | `Stack` with overlapping `CircleAvatar` |
| verified check, crown, star, all icons | `SvgPicture.string(...)` reusing the exact SVG path data from the HTML |

---

## 8. Reusable widget catalog

Build these first — they cover ~90% of every screen.

```dart
// SoftCard — the ubiquitous container
class SoftCard extends StatelessWidget {
  final Widget child; final EdgeInsets padding; final Color? fill; final bool border;
  const SoftCard({super.key, required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.cardPad), this.fill, this.border = true});
  @override Widget build(BuildContext ctx) {
    final c = ctx.colors;
    return Container(padding: padding, decoration: BoxDecoration(
      color: fill ?? c.card, borderRadius: BorderRadius.circular(AppRadii.card),
      border: border ? Border.all(color: c.line) : null, boxShadow: AppShadows.card),
      child: child);
  }
}

// PressScale — signature tactile feedback + haptic
class PressScale extends StatefulWidget {
  final Widget child; final VoidCallback? onTap; final double scale;
  const PressScale({super.key, required this.child, this.onTap, this.scale = .96});
  // GestureDetector → AnimatedScale(160ms, AppMotion.easing); onTap → HapticFeedback.selectionClick()
}

// RiseIn — entrance animation with optional stagger delay
class RiseIn extends StatelessWidget { final Widget child; final int index; /* delay = index*55ms */ }

// OtpInput — 6 boxes, auto-advance/paste/backspace, returns String
class OtpInput extends StatefulWidget { final int length; final ValueChanged<String> onChanged; }
```

Helper snippets `Pill`, `PrimaryButton`, `GhostButton`, `LabeledTextField`, `SectionHeader`, `AppTopBar`, `AppToast.show(context, msg)`, `showAppSheet(context, child)` follow the same token-driven pattern.

Access tokens via an extension for terseness (works in any widget):
```dart
extension ThemeX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}
// GetX also lets you read them without a context, e.g. in controllers/snackbars:
AppColors get appColors => Get.theme.extension<AppColors>()!;
```

---

## 9. App shell & navigation

Bottom nav = **Home · Post · Doxy · CME · Refer**, with **Doxy** a prominent *raised* centre button (48×48 circular mascot PNG lifted ~24 px above the bar with a drop shadow).

GetX has no `ShellRoute`; use the idiomatic pattern — a **`RootScreen`** hosting an `IndexedStack` driven by a `RootController` (an `RxInt` current index). `IndexedStack` keeps each tab's widget alive, preserving its scroll position and internal state exactly like a shell route.

```dart
class RootController extends GetxController {
  final tab = 0.obs;                       // 0 Home · 1 Post · (2 Doxy=push) · 3 CME · 4 Refer
  void select(int i) { tab.value = i; HapticFeedback.selectionClick(); }
}

class RootScreen extends GetView<RootController> {
  @override Widget build(BuildContext ctx) {
    final pages = const [HomeScreen(), PostScreen(), SizedBox(), CmeHome(), ReferralScreen()];
    return Scaffold(
      body: Obx(() => IndexedStack(index: controller.tab.value, children: pages)),
      bottomNavigationBar: const AppBottomNav(),
    );
  }
}

// AppBottomNav — 5 slots; centre is a raised Doxy button
Widget build(BuildContext ctx) {
  final c = ctx.colors; final root = Get.find<RootController>();
  return Obx(() => Container(
    decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
    padding: EdgeInsets.only(top: 9, bottom: 22 + MediaQuery.of(ctx).padding.bottom), // max(22, safe-area)
    child: Row(children: [
      _navItem(root, home, 'Home', 0),
      _navItem(root, post, 'Post', 1),
      _DoxyButton(),                        // Transform.translate(y:-24), 48px circle, shadow, PNG
      _navItem(root, cap,  'CME',  3),
      _navItem(root, refer,'Refer',4),
    ]),
  ));
}
```

`_DoxyButton` does `Get.toNamed(AppRoutes.doxy)` (a full-screen push, not a tab). Active tab colour = `brand`, inactive = `muted`; label 11 px/500; tap → `RootController.select` (haptic) + scale-press. Detail pages (`speakers`, `cme-details`, `create-*`, `notifications`, `settings`, etc.) are separate `GetPage`s pushed with `Get.toNamed(...)` **above** `RootScreen` (full-screen, no bottom nav), each using `AppTopBar` with a back button.

`AppTopBar` reproduces `global.css .topbar`: 40×40 rounded-square back button (`line` border, `brand` on hover/press-scale), ellipsised bold 17 px title, optional right actions.

---

## 10. Data model & persistence

The mockups persist everything in `localStorage`. **In the real app these become server-owned** — each key maps to an API resource (§3.5); `GetStorage`/Hive is only the **local read-through cache + offline mirror**, refreshed by API responses and real-time events. The table below is the canonical field list regardless of transport.

| Key | Type | Meaning | Feature |
|---|---|---|---|
| `docAuth` | `"1"` | signed-in flag | auth guard |
| `docName` | string | display name (`Dr. …`) | profile |
| `docUser` | string | email / login id | auth |
| `docPhone` | string | mobile | settings |
| `docRegNo` | string | medical registration number | registration |
| `docCouncil` | string | State Medical Council (full name) | registration |
| `docRegYear` | string | year of registration | registration |
| `docFather` | string | father's name (from register) | registration |
| `docRole` | string | designation | profile |
| `docWorkplace` | string | current workplace | profile |
| `docCity` | string | city | profile |
| `docAbout` | string | bio | profile |
| `docExperience` | JSON `[{org,role,years}]` | past experience | onboarding |
| `docRegMismatch` | `"0"/"1"` | register-details deviation flag | reconciliation |
| `docRegDeviation` | string | user-noted deviation | reconciliation |
| `docRegReminderDate` | date string | last daily reminder shown | reconciliation |
| `docAvail` | `available\|notavail\|traveling` | availability | profile |
| `docPlan` | `free\|premium\|lapsed` | subscription | profile |
| `cmeTheme` | brand id | selected theme | theming |
| `savedCMEs` | JSON list | bookmarked CMEs | cme |
| `cmeVideoProgress` | JSON map | per-video % | cme-video |
| `cmePrograms` / `cmeDrafts` | JSON | hosted programs / drafts | create-cme |
| `referrals` | JSON list | referrals sent/received | referral |
| `casePosts` | JSON list | case discussion posts | network |
| `myGroups` | JSON list | groups | network |
| `credentials` | JSON list | uploaded credentials | profile |
| `clinicalProfile` | JSON | specialties/languages | profile |
| `hospitalAffiliations` | JSON list | affiliations | profile |
| `accreditationRequests` | JSON list | medico-legal requests | medicolegal |
| `notifications` | JSON list | notifications (deletable) | notifications |
| `profileNudgeDismissed` | flag | hide profile-completion nudge | home |

Model these with **freezed** (e.g. `DoctorProfile`, `Referral`, `CmeProgram`, `AppNotification`, `Experience`, `AccreditationRequest`). A permanent **`SessionService`** (extends `GetxService`) reads/writes the `doc*` keys via `GetStorage` and exposes them as `.obs`; feature controllers own the rest. For production, back these with the real API (via `dio`) and keep `GetStorage`/Hive as cache/offline.

---

## 11. Page catalog

Each entry: **route · what it is · key widgets · state.** Grouped by module (matches §1).

### Auth — `features/auth`
- **`/login` LoginScreen** — segmented **Login / Register** + reset-password sub-flow.
  - *Login:* `LabeledTextField` (email/mobile), password with eye, "Forgot password?" → reset flow, `PrimaryButton`, "Continue with OTP", link to register.
  - *Register wizard (4 steps, progress bar):* see §12.1.
  - *Reset password (3 steps):* see §12.2.
  - State: `AuthController` (GetX) — `.obs` fields for mode, wizard step, form values, OTP digits, resend timer; provided by `AuthBinding`.

### Home — `features/home`
- **`/home` HomeScreen** — greeting header (name from `docName`) + bell (→ notifications) + avatar (→ profile); **registration-reconciliation banner** (§12.3); profile-completion nudge (ring); search; **3-col module grid** (`.modules`); "Popular doctors" carousel (`.pcard` with aligned Connect buttons); feature cards. Widgets: `SectionHeader`, `SoftCard`, `Pill`, `GridView`, horizontal carousels, `CircularProgress` ring.
- **`/notifications` NotificationsScreen** — grouped Today/Earlier list; swipe/trash to delete; "Clear all"; empty state. State: `NotificationsController` over the `notifications` list (`RxList`).

### Network & Posts — `features/network`
- **`/network`** — message icon + profile top bar, search, connections/feed. **`/post`** — "Post" title + create (+) + profile; search; feed of case posts. **`/post-case`, `/create-group`, `/group`, `/case-discussions`, `/explore`, `/specialties`** — creation forms + browse lists (`SoftCard` lists, `ChipRow` filters, `AdaptiveDropdown`).

### CME — `features/cme`
- **`/cme` CmeHome** — search, **CME progress** ring card, quick-action chips (Host/Explore/My Learning/Calendar/Certificates), **Live now** featured card (with LIVE badge, **International Faculty** badge, **N-days** pill, date range), **Recommended** list, **Browse by specialty** row, **Upcoming CMEs** soft-card list (multi-day date range + N-days pill), **Top speakers** carousel.
- **`/cme/details`** — program detail. **`/cme/sessions`** — video list with per-video progress rings. **`/cme/video`** — player + AI summary + key points, writes `cmeVideoProgress`. **`/cme/create`** — host wizard (`cmeDrafts`/`cmePrograms`). **`/my-programs`, `/mylearning`, `/saved-cmes`** — hosted / learning / saved. **`/speakers`** — live-session detail: banner with **date range**, tabs (About/Agenda/Speakers/…), **full multi-day agenda sheet** (Day 1/2/3 tabs, §12.4), speaker profile sheets.

### Referral *(owned)* — `features/referral`
- **`/referral`** — Sent/Active/Completed stats, referral cards (name ellipsised), cancel / change-doctor for pending/declined (doctor-picker sheet). **`/referral/create`** — new referral form. State: `ReferralController` over `referrals` (`RxList`).

### Medico-Legal *(owned)* — `features/medicolegal`
- **`/medicolegal`**, **`/accreditation-requests`**, **`/create-accreditation-request`** — request lists + creation forms (`accreditationRequests`).

### Doxy — `features/doxy`
- **`/doxy` DoxyScreen** — AI assistant chat (typing indicator uses `blink` keyframe → animated dots).

### Profile & Settings — `features/profile`, `features/settings`
- **`/profile` ProfileScreen** — identity card (avatar, name, NMC badge, headline = designation·workplace·city, **Edit profile** + Change photo), availability segmented control, **Medical registration** card (verified/locked, or **pending-mismatch** state with reconcile CTA §12.3), **About** (if set), premium banner, stat tiles, Saved/Practice/Account row lists. **Edit-profile sheet** (§ profile update). Appearance sheet.
- **`/clinical-profile`, `/hospital-affiliations`, `/credentials`, `/credential-add`, `/files`, `/presentations`, `/devices`** — detail/list/upload screens.
- **`/settings` SettingsScreen** — **Account** card (Change **phone** / **email** via OTP sheet; **password** via current+new+confirm sheet), **Preferences** rows, Appearance sheet, legal links, Sign out.

### Reference
- **`/typography`** — living type-scale spec (dev reference). **`index`** — mockup launcher (not shipped).

---

## 12. Key flows (state machines)

### 12.1 Registration wizard (4 steps)
`Verify identity → OTP → Prefilled details → Workplace`
1. **Verify:** registration number + **State Medical Council** (adaptive dropdown, 16 councils) + mobile → Send OTP.
2. **OTP:** 6-box `OtpInput`, masked destination, 30 s resend countdown → Verify.
3. **Prefilled details** (from mock National Medical Register lookup): Year / Reg no. / Council / Name / Father's name shown **locked**; a **"Some details don't match"** toggle captures a deviation (sets `docRegMismatch`); + email & password → Create account.
4. **Workplace:** current workplace (org/designation/city, **mandatory**) + repeatable **past experience** (optional) → Finish → home.
Persist all `doc*` keys; `docAuth=1`. Model the step index + per-step validation as `.obs` fields in the `AuthController` (register sub-state), driving the progress bar and button-enabled states via `Obx`.

### 12.2 Reset password (3 steps)
`Account (email/mobile) → OTP → New + Confirm password`. Confirm must match (inline error, min 6). On success → back to Login prefilled. Reuse `OtpInput` + resend countdown from the register flow.

### 12.3 Registration-mismatch reconciliation + **daily reminder**
If `docRegMismatch == "1"`:
- **Home** shows a persistent amber banner ("Reconcile your registration") **and** fires a reminder **once per calendar day** — gate on `docRegReminderDate != today` (a toast + optional notification), then stamp today.
- **Profile** Medical-registration card flips to a "Verification pending · differs from NMC" state with the noted deviation and a **"Records now match — clear reminder"** action that clears `docRegMismatch/Deviation/ReminderDate`.
Implement the daily gate in a permanent `SessionController` that implements `WidgetsBindingObserver` and re-checks on `didChangeAppLifecycleState → AppLifecycleState.resumed` (and on first launch) — do **not** use a fixed timer.

### 12.4 CME multi-day agenda
Live-session banner shows a **derived date range** (1 day → "24 May 2025", 2 → "24–25 May 2025", 3 → cross-month aware). **View full agenda** opens a sheet with **Day 1/2/3 tabs**, each a timeline. N-day programs surface a "N days" pill + range on CME cards; single-day shows just the date. Keep it data-driven (`days`, optional `endDate`).

---

## 13. Animation & micro-interaction spec

| Interaction | Spec |
|---|---|
| Entrance | fade + `translateY(12→0)`, 500 ms, `Cubic(.22,1,.36,1)`, list stagger ~55 ms |
| Press | `scale → 0.9–0.98`, 160 ms + `HapticFeedback.selectionClick()` |
| Bottom sheet | slide up 420 ms; drag handle; scrim `rgba(15,15,35,.5)`; drag-to-dismiss |
| Toast | fade+rise in, hold 1.4 s, fade out; dark pill bottom-centre |
| Theme switch | `AnimatedTheme` cross-fade via `AppColors.lerp` |
| Live/pulse dot | opacity pulse (CSS `pulse`) → `AnimatedOpacity` loop |
| Typing dots (Doxy) | staggered bounce (CSS `blink`) → 3 `AnimatedContainer`s |
| Progress ring fill | animate sweep from 0 to value, 900 ms `easing` |
| OTP box focus | border → brand + soft focus ring (3 px `brandSoft`) |

Prefer implicit animations (`AnimatedContainer/Opacity/Scale/Align`) for state changes; `AnimationController` only for entrance/looping.

---

## 14. Accessibility & responsiveness

- **A11y:** `Semantics` labels on icon-only buttons (the mockups already carry `aria-label`s — reuse the text); min tap target 44–48 dp (nav items are 48); honour `MediaQuery.textScaler` — the type scale is in logical px so it scales; check contrast in White/Colour themes.
- **Responsive:** the mock is a fixed 390-frame; in Flutter use real `MediaQuery`. Base paddings on `AppSpacing`; let text wrap; wide rows (tables, timelines) scroll horizontally. Ease h1/h2 on <360 dp (matches the CSS `@media (max-width:360px)`).

Performance, memory, loaders, security and connectivity are covered in §14.1–14.4.

---

## 14.1 Performance, memory & lifecycle (no leaks)

**GC reality:** Dart's garbage collector is automatic — you cannot "run" it. Preventing leaks = **removing lingering references** (open subscriptions, timers, controllers, static caches). GetX helps: controllers created via a `Binding`'s `lazyPut` are **auto-disposed when their route pops**. Only `permanent: true` singletons (`ThemeController`, `SessionService`, `ApiClient`, `Bus`, `RealtimeService`, `ConnectivityService`) live for the app's lifetime.

**Every controller must clean up in `onClose()`** — this is the #1 leak source:

```dart
class SpeakersController extends GetxController {
  final _subs = <StreamSubscription>[];
  Timer? _resend;
  final search = TextEditingController();
  final scroll = ScrollController();
  final CancelToken _cancel = CancelToken();          // cancel in-flight dio calls

  @override void onInit() {
    super.onInit();
    _subs.add(Get.find<Bus>().on<CmeLiveUpdated>().listen(_onLive)); // manual listen → must cancel
    debounce(_query, _runSearch, time: 300.ms);        // GetX worker → auto-disposed with controller
  }

  @override void onClose() {
    for (final s in _subs) { s.cancel(); }             // ← cancel EventBus / realtime subscriptions
    _resend?.cancel();                                 // ← cancel timers (OTP countdown, etc.)
    search.dispose(); scroll.dispose();                // ← dispose text/scroll controllers
    _cancel.cancel('view closed');                     // ← abort pending requests
    super.onClose();
  }
}
```

Checklist:
- **Cancel** every `StreamSubscription` (EventBus, realtime, connectivity) in `onClose`; prefer GetX **workers** (`ever/debounce/once/interval`) which auto-dispose with the controller.
- **Dispose** `TextEditingController`, `ScrollController`, `AnimationController`, `FocusNode`, `PageController`, and cancel `Timer`s.
- **Abort network** with a `CancelToken` per controller (kills "setState-after-dispose"/callback-after-pop bugs).
- Don't hold `BuildContext`/widgets in controllers; don't keep unbounded `static` caches or global lists.
- **On logout:** `RealtimeService.disconnect()`, `Get.deleteAll()` (drops non-permanent controllers), wipe caches & secure storage (§14.3).
- **Render perf:** `const` everywhere; `ListView.builder`/slivers (never a giant `Column`); `itemExtent`/`prototypeItem` for fixed rows; `RepaintBoundary` around animated cards & rings; keep **`Obx` scopes tiny** (wrap only the reactive widget); `GetBuilder` for non-reactive one-shot UI; `cacheWidth`/`memCacheWidth` on images so full-res isn't decoded.
- **Tabs:** `IndexedStack` keeps tabs alive by design (preserves scroll); if a tab is heavy, lazy-build it on first visit.
- **Verify:** DevTools **Memory** + Flutter's **`leak_tracker`** in widget tests; watch for controllers/subscriptions that survive a pop.

## 14.2 Loaders & loading states

Every async screen is driven by the `Status` enum on its ViewModel (§3.5) — no ad-hoc spinners. Use **skeletons** for content (shape-matching, not a centered spinner) and **inline** spinners for actions.

```dart
class StatusView<T> extends StatelessWidget {
  final Rx<Status> status; final Widget Function() success;
  final Widget? skeleton; final VoidCallback onRetry;
  @override Widget build(BuildContext c) => Obx(() => switch (status.value) {
    Status.loading => skeleton ?? const CardSkeleton(),      // shimmer/Skeletonizer
    Status.empty   => const EmptyState(),
    Status.error   => ErrorRetry(onRetry: onRetry),
    _              => success(),
  });
}
```

Rules:
- **Skeleton loaders** (shimmer / `skeletonizer`) sized like the real cards → **no layout jump** when data lands.
- **Buttons**: on submit, show an inline spinner + **disable** the button (prevents double OTP/submit). An `AsyncButton` that takes a `Future` and manages its own busy state.
- **Blocking overlay** (`Get.dialog(barrierDismissible:false)`) only for truly blocking ops (creating account) — used sparingly.
- **Pull-to-refresh** (`RefreshIndicator`) on every feed; **pagination** with a footer loader for infinite lists.
- **Timeouts always resolve to an error state with Retry** — never an infinite spinner.
- Reuse the mock's `.toast` as `AppToast` for transient success/error; use skeletons for initial load.

## 14.3 Security

A medical app handles PII + registration data — treat it accordingly.

- **Secrets & PII → `flutter_secure_storage`** (iOS Keychain / Android Keystore), **never** `GetStorage`/SharedPreferences. Access/refresh tokens, and cache of `docRegNo`/`docFather`/contact live there; only non-sensitive UI prefs (theme) stay in `GetStorage`.
- **Transport:** HTTPS only; add **certificate pinning** in dio (`badCertificateCallback` / a pinning interceptor). Reject cleartext (`android:usesCleartextTraffic=false`).
- **Auth:** short-lived access token + refresh; the dio **refresh interceptor** queues on `401`, refreshes once, replays; on refresh failure → `AuthChanged(false)`, wipe secure storage, route to login.
- **OTP is server-verified** (the mock accepts any 6 digits — must not ship). Enforce expiry + rate-limit server-side; never reveal the code client-side.
- **Device integrity:** root/jailbreak + emulator detection (`flutter_jailbreak_detection`) — warn or restrict on compromised devices.
- **Screen protection:** flag sensitive screens (referrals, medico-legal, registration) `FLAG_SECURE` (Android) / obscure on app-switcher (iOS) to block screenshots/recording of patient data.
- **App lock (optional):** `local_auth` biometric lock; re-authenticate on `resumed` after an idle timeout.
- **Input validation & sanitisation** (reg no, email, phone) client-side for UX, **server is authoritative**.
- **Release hardening:** build `--obfuscate --split-debug-info=…`; strip logs in release (`if (kDebugMode)` guards, no PII in logs/crash reports); scrub tokens from Dio logs.
- **Don't trust push/deep-link payloads** — treat them as an id, then fetch the record over authenticated API.
- **Compliance:** the mockups state *"Data residency: India (DPDP)"* — keep PII in-region, capture consent, support data export/delete.

## 14.4 Network & connectivity

- **`ConnectivityService`** (`GetxService`, permanent) wraps `connectivity_plus` and exposes `RxBool online`. A slim **offline banner** appears app-wide when down; write actions disable/queue. Emits `ConnectivityChanged` on the `Bus`.
  ```dart
  class ConnectivityService extends GetxService {
    final online = true.obs;
    @override void onInit() {
      super.onInit();
      Connectivity().onConnectivityChanged.listen((r) {
        online.value = !r.contains(ConnectivityResult.none);
        if (online.value) Get.find<SyncQueue>().flush();   // replay queued writes
      });
    }
  }
  ```
- **dio timeouts** (`connectTimeout`/`receiveTimeout` ~15 s) + a **retry interceptor** with exponential backoff for **idempotent GETs** only.
- **Offline-first:** render from cache first, refresh in background; **optimistic writes** update UI + cache immediately, enqueue the API call, and **roll back on failure**; a `SyncQueue` flushes when `online` returns.
- **`connectivity_plus` reports the interface, not real reachability** — optionally confirm with a lightweight `/health` probe before trusting "online".
- **Map every failure class** to distinct UX via `AppException`: timeout, no-network, `401` (refresh), `403`, `404`, `5xx` → retry / login / message.
- **Realtime resilience:** `RealtimeService` auto-reconnects with backoff, resends subscriptions, uses heartbeat/ping; **on reconnect, refetch** affected resources to fill any gap missed while offline.
- **Cancel in-flight requests** on screen dispose via the controller's `CancelToken` (§14.1).

---

## 15. "Better than native" checklist

- [ ] Identical, brand-perfect visuals on iOS **and** Android (native apps usually favour one).
- [ ] Platform-correct transitions, scroll physics, back gesture, haptics, pickers (§6).
- [ ] Global, consistent motion language (press-scale, staggered rise, theme lerp).
- [ ] 5 brand themes **+** system light/dark, switchable instantly, persisted.
- [ ] Hairline-defined cards in every theme (no "washed out" white theme).
- [ ] 60/120 fps — `const`, builders, repaint boundaries; small `Obx` scopes (§14.1).
- [ ] **Zero leaks** — every controller cleans up in `onClose` (subs/timers/controllers/`CancelToken`); verified with `leak_tracker` (§14.1).
- [ ] **Proper loaders** — skeletons (no layout jump), busy/disabled buttons, retry on error, never an infinite spinner (§14.2).
- [ ] **Security** — PII/tokens in secure storage, cert pinning, refresh-on-401, server-verified OTP, screenshot-protected sensitive screens, obfuscated release (§14.3).
- [ ] **Network-aware** — offline banner, timeouts+retry, offline-first cache with optimistic writes + sync queue, realtime auto-reconnect (§14.4).
- [ ] Offline-first via Hive/GetStorage cache of the `doc*`/feature keys.
- [ ] Full a11y (labels, contrast, text scaling) — often skipped in native.

---

## 16. Suggested milestones

1. **Foundation** — `GetMaterialApp`, tokens, `AppColors` extension, `TextTheme`, `buildTheme`, `ThemeController` + `InitialBinding` + `GetStorage` persistence, widget catalog (§8), adaptive layer (§6).
2. **Core services (event-driven + API, §3.5)** — `ApiClient` (dio + auth/refresh/error interceptors + cert pinning), `SessionService` (secure storage), `Bus` (EventBus), `RealtimeService` (WS/SSE) + FCM, `ConnectivityService` + `SyncQueue` (§14.4), `Status` pattern + `StatusView`/skeletons (§14.2), lifecycle/leak conventions (§14.1), repositories + freezed models/DTOs, offline cache.
3. **Shell & nav** — `RootScreen` + `IndexedStack` + `RootController`, `AppBottomNav` (raised Doxy), `AppTopBar`, `AppPages`/`AppRoutes` + bindings, auth `GetMiddleware`.
4. **Auth** — login + 4-step register wizard + reset flow + OTP/countdown (§12.1–12.2), wired to `/auth/*` endpoints.
5. **Home + Profile + Settings** — including reconciliation reminder (§12.3), edit-profile, account changes; wired to `/me`.
6. **CME** — home, details, sessions/video, multi-day agenda (§12.4); live counts via `CmeLiveUpdated`.
7. **Network/Posts, Referral, Medico-Legal, Doxy** — real-time referral/notification/chat events.
8. **Polish** — animations, a11y, dark mode, performance pass; harden API error/offline states and push deep-links.

---

## 17. Pre-flight & delivery concerns

The sections above cover *how screens are built*. This section captures everything else a production **medical** app needs. **★ = specific to this app** (doctor/medical/India-DPDP). Treat P0 as *decide before writing feature code*.

### P0 — architectural decisions (do first)

- [ ] **★ Payments / subscriptions.** Premium/Free/Lapsed (₹2,499/mo) on Profile needs a real billing plan. Apple/Google **require in-app purchase for digital subscriptions** (`in_app_purchase`, StoreKit/Play Billing) — Razorpay only for out-of-app/physical goods. Server-side receipt validation, restore purchases, grace/lapsed handling, entitlement gating. → `in_app_purchase`
- [ ] **★ CME video pipeline.** Real player + streaming + resume + (paid) DRM + optional offline download. This is a subsystem, not a widget. → `video_player` + `chewie` (or `better_player`), HLS, Widevine/FairPlay for paid content, resume via `cmeVideoProgress`.
- [ ] **★ Environments & flavors.** dev / staging / prod flavors, `--dart-define`/`.env`, per-env base URLs & keys, feature flags. Retrofitting later is painful. → `flutter_flavorizr` (optional), `--dart-define-from-file`.
- [ ] **★ Backend API contract (teammate alignment).** Agree an **OpenAPI/Swagger** spec, shared **error envelope**, pagination shape, `/v1` versioning. Extract tokens + shared widgets into a **`core` design-system package** so the two of you don't diverge. → melos monorepo or a shared package.
- [ ] **★ Compliance & medical/legal.** DPDP (India) data residency + consent capture; **Doxy AI medical-advice disclaimer** ("not a substitute for clinical judgment"); medico-legal **audit logging**; data retention/export/delete; NMC verified-physician gating enforced **server-side**.
- [ ] **Write idempotency.** Idempotency keys on all POSTs so retry/optimistic/sync-queue (§14.4) can't double-submit a referral or OTP.

### P1 — before launch

- [ ] **Testing.** Unit (controllers/repos), widget, **golden tests** (critical — token-driven design × 5 themes), integration/e2e, coverage gate. → `mocktail`, `golden_toolkit`/`alchemist`, `patrol` or `integration_test`.
- [ ] **Crash reporting + analytics.** Crashlytics/Sentry; event funnels (registration drop-off first); PII-scrubbed remote logs. → `firebase_crashlytics` or `sentry_flutter`, `firebase_analytics`.
- [ ] **Push notifications (full setup).** FCM/APNs, **runtime permission** (iOS + Android 13 `POST_NOTIFICATIONS`), Android channels, background/terminated handlers, cold-start-from-push routing. → `firebase_messaging`, `permission_handler`.
- [ ] **★ Local (scheduled) notifications.** The registration-mismatch "remind daily" and CME session reminders must fire when the app is **closed** — schedule OS notifications, not just on-resume. → `flutter_local_notifications` (zoned schedule) + `timezone`.
- [ ] **Runtime permissions & files.** Camera (photo/credential scan), document picker + PDF viewer + upload progress + size limits for `credentials`/`presentations`/`files`; denied/rationale states. → `permission_handler`, `file_picker`, `image_picker`, `syncfusion_flutter_pdfviewer`/`pdfx`.
- [ ] **Force-update / kill-switch / maintenance mode.** Min-supported-version gate via remote config. → `firebase_remote_config`, `upgrader`.
- [ ] **Auth session lifecycle.** Idle auto-logout for medical data, token-expiry UX, biometric re-auth on resume, deep-link auth guards (`GetMiddleware`).
- [ ] **Localization infra** (even if English-only at launch): ₹ currency, **IST dates/timezones** (CME schedules are TZ-sensitive), future Hindi/regional. → `flutter_localizations`, `intl`.
- [ ] **State restoration** (Android process death) — don't lose a half-filled 4-step registration. → `RestorationMixin`.
- [ ] **Deep links / app links / universal links** — verified domains, notification/referral link routing.

### P2 — quality & scale

- [ ] **Dark mode design** — mockups are light-only; each token needs a dark value + per-theme status-bar contrast (structure exists in §5, values don't).
- [ ] **Asset optimization** — `assets/doxy.png` is **~1.5 MB**; compress, provide @2x/@3x, tree-shake icons, subset Inter, watch bundle size.
- [ ] **Form UX** — input formatters (phone/reg-no), keyboard types, autofill, keyboard-avoidance (scroll-to-focused-field), focus traversal.
- [ ] **Search & pagination contracts** — debounce + server search + history + no-results; consistent stale-while-revalidate cache policy.
- [ ] **Device/orientation matrix** — min iOS/Android versions, portrait-lock decision, tablet/foldable behaviour.
- [ ] **CI/CD** — signing, staged rollout, store metadata. → Fastlane / Codemagic / GitHub Actions.
- [ ] **Accessibility deep pass** — TalkBack/VoiceOver run-through, dynamic-type extremes, colour-blind-safe status colours.

### Most underestimated (scope these explicitly)
1. **Payments + CME video/DRM** are each multi-week subsystems, not screens.
2. **Teammate API contract + shared design package** — without it, two devs on an undefined backend produce merge/UX drift.
3. **Idempotency + offline sync conflicts** — the optimistic/offline model is only safe with idempotency keys and a defined conflict policy.

---

### Appendix A — token quick-reference (Ocean, the default)
`brand #1e5fbf · brandDark #164a99 · brandSoft #e7effc · gold #b0894f · ink #0f2438 · slate700 #31465e · muted #546a80 · line #e1e9f3 · chip #eef4fb · green #1f9d6b · surface #fff · card #fff · soft1 #e9f1ff · soft2 #eaf3ff`. Header gradient `#4f8be8→#1e5fbf`; hero gradient `#0b2545→#123a72→#1e5fbf`.

### Appendix B — reuse the SVGs
Every icon in the app is inline SVG in the HTML. Extract the `<svg>…</svg>` strings into a Dart `AppIcons` map and render with `SvgPicture.string`. This guarantees pixel-identical icons and saves redrawing them.
