import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:void_raid/main.dart';
import 'package:void_raid/services/ad_service.dart';
import 'package:void_raid/services/progress_store.dart';
import 'package:void_raid/services/sound_service.dart';

void main() {
  testWidgets('start a game from the home screen, pause and quit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressStore.open();
    final sound = NoSound();
    await tester.pumpWidget(VoidRaidApp(progress: progress, ads: const NoAdService(), sound: sound));
    expect(find.text('VOID'), findsOneWidget);

    await tester.tap(find.byKey(const Key('play')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('LEVEL 1'), findsNothing); // intro banner has faded
    expect(find.byKey(const Key('score')), findsOneWidget);
    expect(sound.played, contains(Sfx.shoot));

    await tester.tap(find.byKey(const Key('pause')));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    await tester.tap(find.text('Quit to menu'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // the home starfield never settles
    expect(find.text('VOID'), findsOneWidget);
  });
}
