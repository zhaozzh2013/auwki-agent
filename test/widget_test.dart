// AUWKI Agent 冒烟测试：首次启动引导 → 主页 → 新建对话。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/i18n/strings.dart';
import 'package:auwki_agent/main.dart';
import 'package:auwki_agent/pages/home_page.dart';
import 'package:auwki_agent/widgets/onboarding_screen.dart';

import 'helpers.dart';

/// 走完首次引导，进入主页。
Future<void> finishOnboarding(WidgetTester tester) async {
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

  testWidgets('AUWKI Agent：引导 → 主页 → 新建对话', (tester) async {
    await tester.pumpWidget(const AuwkiAgentApp());
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text(I18n.t('onboarding.page1.title')), findsOneWidget);

    await finishOnboarding(tester);

    expect(find.text(I18n.t('mode.work')), findsWidgets);

    await tester.tap(find.text(I18n.t('sidebar.new_chat')));
    await tester.pumpAndSettle();

    expect(find.text(I18n.t('chat.placeholder')), findsOneWidget);
  });

  testWidgets('引导支持“跳过”', (tester) async {
    await tester.pumpWidget(const AuwkiAgentApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text(I18n.t('onboarding.skip')));
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
  });
}
