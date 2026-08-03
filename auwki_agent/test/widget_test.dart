// AUWKI Agent 冒烟测试：验证应用能正常构建首页并新建对话。
import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/i18n/strings.dart';
import 'package:auwki_agent/main.dart';
import 'package:auwki_agent/pages/home_page.dart';

void main() {
  testWidgets('AUWKI Agent renders the home page', (tester) async {
    await tester.pumpWidget(const AuwkiAgentApp());
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text(I18n.t('home.onboarding.title')), findsOneWidget);
    expect(find.text(I18n.t('mode.work')), findsWidgets);

    // 新建对话后应出现输入框（无崩溃）。
    await tester.tap(find.text(I18n.t('sidebar.new_chat')));
    await tester.pumpAndSettle();

    expect(find.text(I18n.t('chat.placeholder')), findsOneWidget);
  });
}
