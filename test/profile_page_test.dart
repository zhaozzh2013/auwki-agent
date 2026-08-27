import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/i18n/strings.dart';
import 'package:auwki_agent/main.dart';
import 'package:auwki_agent/pages/home_page.dart';
import 'package:auwki_agent/pages/profile_page.dart';
import 'package:auwki_agent/widgets/onboarding_screen.dart';

import 'helpers.dart';

Future<void> _finishOnboarding(WidgetTester tester) async {
  expect(find.byType(OnboardingScreen), findsOneWidget);
  for (var i = 0; i < 3; i++) {
    await tester.tap(find.text(I18n.t('onboarding.next')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(I18n.t('onboarding.start')));
  await tester.pumpAndSettle();
  expect(find.byType(HomePage), findsOneWidget);
}

void main() {
  late Directory dataDir;

  setUp(() {
    dataDir = mockPathProvider();
  });

  tearDown(() {
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  });

  testWidgets('点击侧边栏用户名打开用户详情页', (tester) async {
    await tester.pumpWidget(const AuwkiAgentApp());
    await tester.pumpAndSettle();
    await _finishOnboarding(tester);

    await tester.tap(find.text(I18n.t('sidebar.user')));
    await tester.pumpAndSettle();

    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.text(I18n.t('profile.stats.tokens')), findsOneWidget);
    expect(find.text(I18n.t('profile.chart.title')), findsOneWidget);

    // 返回主页
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
  });
}
