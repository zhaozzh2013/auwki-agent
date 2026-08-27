import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/app_state.dart';
import 'package:auwki_agent/i18n/strings.dart';
import 'package:auwki_agent/services/chat_database.dart';
import 'package:auwki_agent/services/settings_store.dart';
import 'package:auwki_agent/state/chat_store.dart';
import 'package:auwki_agent/state/round_changes_store.dart';
import 'package:auwki_agent/widgets/dialogs/settings_dialog.dart';

import 'helpers.dart';

void main() {
  late Directory dataDir;
  late Directory mockDir;

  setUp(() {
    dataDir = Directory.systemTemp.createTempSync('settings_dlg_test');
    ChatDatabase.instance.close();
    mockDir = mockPathProvider(hermetic: true);
  });

  tearDown(() {
    ChatDatabase.instance.close();
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
    if (mockDir.existsSync()) mockDir.deleteSync(recursive: true);
  });

  Future<SettingsStore> pumpApp(
    WidgetTester tester, {
    Map<String, dynamic>? seed,
  }) async {
    if (seed != null) {
      final support = Directory('${mockDir.path}/support');
      support.createSync(recursive: true);
      File('${support.path}/settings.json')
          .writeAsStringSync(jsonEncode(seed));
    }
    final settings = SettingsStore();
    final store = ChatStore(storageDir: dataDir);

    await tester.pumpWidget(
      MaterialApp(
        home: AppState(
          chat: store,
          settings: settings,
          roundChanges: RoundChangesStore(),
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showSettingsDialog(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return settings;
  }

  testWidgets('异常保留天数不会导致设置页崩溃', (tester) async {
    await pumpApp(
      tester,
      seed: {
        'retentionDays': 60,
        'onboardingSeen': true,
      },
    );
    expect(find.text(I18n.t('settings.title')), findsOneWidget);
  });

  testWidgets('设置对话框可打开（供应商设置入口 + 代理 + 预设）', (tester) async {
    await pumpApp(tester);

    expect(find.text(I18n.t('settings.title')), findsOneWidget);
    expect(find.text(I18n.t('settings.provider_manage')), findsWidgets);
    expect(find.text(I18n.t('settings.preset')), findsOneWidget);
    expect(find.text(I18n.t('settings.proxy')), findsOneWidget);
  });

  testWidgets('二级菜单：供应商设置可打开（多供应商路由 + API Key 隐藏）', (tester) async {
    await pumpApp(tester);

    // 点击“供应商设置”入口卡片（以图标定位）。
    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pumpAndSettle();

    // 二级菜单页面内容。
    expect(find.text(I18n.t('settings.model')), findsOneWidget);
    expect(find.text(I18n.t('settings.test_connection')), findsOneWidget);
    expect(find.text(I18n.t('settings.multi_provider')), findsOneWidget);

    // API Key 隐藏态：标准密码框 + 显示按钮；切到显示后出现隐藏按钮。
    expect(find.byIcon(Icons.visibility), findsWidgets);
    final showBtn = find.byIcon(Icons.visibility).first;
    await tester.ensureVisible(showBtn);
    await tester.pumpAndSettle();
    await tester.tap(showBtn);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });

  testWidgets('API Key 输入后立即写入设置并回显', (tester) async {
    final settings = await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pumpAndSettle();

    expect(settings.apiKey, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('api_key_hidden')),
      'sk-test-12345',
    );
    await tester.pump();

    // 输入即生效：SettingsStore 已拿到新 Key。
    expect(settings.apiKey, 'sk-test-12345');

    // 关闭后重新打开对话框，应回显已保存的 Key。
    await tester.tap(find.text(I18n.t('git.close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pumpAndSettle();
    final reopened = tester.widget<TextField>(
      find.byKey(const ValueKey('api_key_hidden')),
    );
    expect(reopened.controller?.text, 'sk-test-12345');
  });
}
