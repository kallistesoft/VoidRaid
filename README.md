# Void Raid

Neon arcade space shooter by Kallistesoft. Play it at https://raid.kallistesoft.ca.

- Every level is a new wave: 6 formations × 5 movement patterns, with new enemy
  kinds unlocking (drones, gunners, armoured tanks, divers) and meteor showers.
- A level ends when the whole wave is destroyed. Speed, fire rate, dive rate and
  enemy count rise each level.
- Every 5th level is a boss (The Warden, Hive Mother, Vortex, Phantom, The Core,
  then they come back with more HP). Each boss enrages at half health.
- Game over sends you back to the level after the last boss beaten; one rewarded
  revive per run.
- Between levels, a break screen with an `AdSlot` (300×250) placeholder and
  `AdService.showInterstitial()` on Continue. Both are no-ops until an ad network
  is wired in (`lib/services/ad_service.dart`, `lib/ui/ad_slot.dart`).

## Code

- `lib/game/levels.dart`: level specs built from the level number, formations.
- `lib/game/world.dart`: the whole simulation in a fixed 360×640 field (pure Dart, tested).
- `lib/ui/`: screens and the canvas renderer. No image assets: everything is drawn.
- `tools/make_sfx.py`: synthesizes the sound effects into `assets/sfx`.

## Run

```
flutter test
flutter run -d chrome
```

Every push to `main` builds and deploys the web version to the GoDaddy hosting
(`.github/workflows/deploy-godaddy.yml`).
