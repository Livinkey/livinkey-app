# Livinkey – Tenant & Guest App

Flutter app (Android, iOS) for Livinkey PG residents and guests. Tenants view and pay bills, upload payment proofs, download receipts, raise maintenance requests, manage documents and vehicle details, read notices and agreements, see their roommates and check out. Guests can browse PGs, offers and submit enquiries.

## Requirements

- Flutter SDK (Dart `^3.10.4`)
- A running [Livinkey backend](../livinkey_admin/backend/README.md) – the API address is `kApiBaseUrl` in `lib/utils/constants.dart`
- Firebase project files for push notifications (`google-services.json` / `GoogleService-Info.plist`)

## Run

```bash
flutter pub get
flutter run
```

Release builds: `flutter build apk --release` / `flutter build appbundle` / `flutter build ios`.

## Project structure

```
lib/
├── main.dart
├── models/            # API models (auth, bills, payments…)
├── services/          # API client, session, push notifications, UPI
├── screens/
│   ├── auth/          # login, OTP, password reset
│   ├── tenant/        # home, payments, maintenance, documents, profile,
│   │                  # roommates, checkout, notices, agreements, vehicle
│   ├── guest/         # guest experience
│   └── common/        # notifications
├── widgets/
│   ├── common/        # snackbars, loaders, skeleton / empty / error states
│   └── tenant/        # receipt sheet, bill cards, chips…
└── utils/             # constants, theme, helpers
assets/images/         # logos (receipt_logo.jpg is used on the paper receipt)
```

## Features of note

- **Payments** – pay by UPI, then attach a screenshot as proof. No transaction ID is typed; the property team reads it from the screenshot.
- **Receipt-style history** – payment history is grouped by month; tapping a payment opens an animated paper receipt (stamp, torn edges) with a *Download PDF* action.
- **Roommate details** – shown in the menu only for tenants who share a room; lists basic contact details of roommates (no financial or ID information).
- **Check out** – from the menu. Blocked while any bill is unpaid; otherwise requires typing `CHECKOUT` to confirm, then signs the tenant out.
- **Money safety** – amounts shown are never negative or NaN; the amount field accepts digits with up to two decimals.
- **Loading & empty states** – skeleton loaders on list screens, friendly empty and error states with retry.
- **Announcements** – messages from the property team are signed with the sender's name.

## Quality checks

```bash
flutter analyze
flutter test
```
