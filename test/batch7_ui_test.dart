import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/app_state.dart';
import 'package:auwki_agent/i18n/strings.dart';
import 'package:auwki_agent/main.dart';
import 'package:auwki_agent/models/models.dart';
import 'package:auwki_agent/pages/home_page.dart';
import 'package:auwki_agent/services/chat_database.dart';
import 'package:auwki_agent/services/settings_store.dart';
import 'package:auwki_agent/theme.dart';
import 'package:auwki_agent/services/ui_state.dart';
import 'package:auwki_agent/widgets/dialogs/guide_dialog.dart';
import 'package:auwki_agent/widgets/onboarding_screen.dart';

import 'helpers.dart';

void main() {
  late Directory dataDir;

  setUp(() {
    dataDir = mockPathProvider(hermetic: true);
    ChatDatabase.instance.close();
  });

  tearDown(() {
    ChatDatabase.instance.close();
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  });

  Future<void> seedSettings(Map<String, dynamic> extra) async {
    final support = Directory('${dataDir.path}/support');
    support.createSync(recursive: true);
    File('${support.path}/settings.json').writeAsStringSync(jsonEncode({
      'provider': 'openai',
      'model': 'gpt-4o-mini',
      'apiKey': '',
      'onboardingSeen': true,
      ...extra,
    }));
  }

  Future<void> pumpApp(WidgetTester tester) async {
    debugPrint('batch7: pumpWidget start');
    final f = File('${dataDir.path}/support/settings.json');
    if (f.existsSync()) {
      final raw = f.readAsStringSync();
      debugPrint('batch7: settings.json len=${raw.length} head=${raw.substring(0, raw.length > 80 ? 80 : raw.length)}');
      try {
        jsonDecode(raw);
        debugPrint('batch7: json ok');
      } catch (e) {
        debugPrint('batch7: json FAIL $e');
      }
    } else {
      debugPrint('batch7: settings.json NOT FOUND');
    }
    await tester.pumpWidget(const AuwkiAgentApp());
    debugPrint('batch7: pumpWidget done');
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    debugPrint('batch7: bounded pumps done');
    debugPrint(
      'batch7: screens home=${find.byType(HomePage).evaluate().length} '
      'onboarding=${find.byType(OnboardingScreen).evaluate().length}',
    );
    expect(find.byType(HomePage), findsOneWidget);
  }

  testWidgets('C01/C02/C08/C15: 主题定制、字体、密度、高对比生效并持久化',
      (tester) async {
    debugPrint('C01: setup');
    await seedSettings({
      'cornerRadius': 1.5,
      'uiDensity': 'compact',
      'uiFont': 'serif',
      'highContrast': true,
    });
    debugPrint('C01: seeded');
    await pumpApp(tester);

    debugPrint('C01: reading theme');
    final ctx = tester.element(find.byType(HomePage));
    final theme = Theme.of(ctx);
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.visualDensity, VisualDensity.compact);
    // 圆角系数 1.5 → 对话框圆角 18
    final dialogShape = theme.dialogTheme.shape as RoundedRectangleBorder;
    expect(dialogShape.borderRadius, BorderRadius.circular(18));

    final settings = AppState.settingsOf(ctx);
    expect(settings.cornerRadius, 1.5);
    expect(settings.uiDensity, UiDensity.compact);
    expect(settings.uiFont, UiFont.serif);
    expect(settings.highContrast, isTrue);
  });

  testWidgets('C05: 快捷键重映射 Ctrl+M 新建对话', (tester) async {
    await seedSettings({
      'shortcutOverrides': {'new_chat': 'm'},
    });
    await pumpApp(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text(I18n.t('chat.placeholder')), findsOneWidget);
  });

  testWidgets('C11: 输入工具栏 Markdown 快捷插入', (tester) async {
    await seedSettings({});
    await pumpApp(tester);
    await tester.tap(find.text(I18n.t('sidebar.new_chat')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('B'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, contains('****'));
  });

  testWidgets('C07: 引导对话框分步可跳过', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showGuideDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('选择模型'), findsOneWidget);
    await tester.tap(find.text(I18n.t('onboarding.next')));
    await tester.pumpAndSettle();
    expect(find.textContaining('调整模式'), findsOneWidget);
  });

  testWidgets('C12: 工具气泡折叠状态切换', (tester) async {
    expect(UiState.collapseTools.value, isFalse);
    UiState.toggleCollapseTools();
    expect(UiState.collapseTools.value, isTrue);
    UiState.toggleCollapseTools();
    expect(UiState.collapseTools.value, isFalse);
  });

  testWidgets('C06: 命令面板覆盖核心入口', (tester) async {
    await seedSettings({});
    await pumpApp(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // 首屏可见项。
    expect(find.text(I18n.t('palette.new_chat')), findsWidgets);
    expect(find.text(I18n.t('palette.settings')), findsWidgets);
    // 列表较长，滚动后确认后置入口。
    await tester.scrollUntilVisible(
      find.text(I18n.t('task.center')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text(I18n.t('task.center')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(I18n.t('settings.storage')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text(I18n.t('settings.storage')), findsOneWidget);
  });
}
