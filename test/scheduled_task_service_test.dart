import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/scheduled_task_service.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('auwki_sched_test');
    ScheduledTaskService.debugFile = File('${tmp.path}/sched.json');
  });

  tearDown(() async {
    await ScheduledTaskService.instance.resetForTest();
    for (var i = 0; i < 5; i++) {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  test('A13: nextFire computes the next due time', () {
    final t = ScheduledTask(
      id: 't1',
      conversationId: 'c1',
      prompt: 'p',
      hour: 9,
      minute: 30,
    );
    final now = DateTime(2026, 8, 10, 8, 0);
    final next = t.nextFire(now);
    expect(next, DateTime(2026, 8, 10, 9, 30));

    final late = DateTime(2026, 8, 10, 10, 0);
    expect(t.nextFire(late), DateTime(2026, 8, 11, 9, 30));
  });

  test('A13: weekly task skips non-matching days', () {
    final t = ScheduledTask(
      id: 't2',
      conversationId: 'c1',
      prompt: 'p',
      hour: 9,
      minute: 0,
      weekdays: const [1], // Monday
    );
    // 2026-08-10 is Monday.
    final next = t.nextFire(DateTime(2026, 8, 10, 8, 0));
    expect(next, DateTime(2026, 8, 10, 9, 0));
    // 2026-08-11 is Tuesday -> next Monday 2026-08-17.
    expect(
      t.nextFire(DateTime(2026, 8, 11, 8, 0)),
      DateTime(2026, 8, 17, 9, 0),
    );
  });

  test('A13: add/remove and tick fires once per day', () async {
    var fired = 0;
    ScheduledTaskService.instance.onFire = (_) async => fired++;
    final t = await ScheduledTaskService.instance.add(
      conversationId: 'c1',
      prompt: 'report',
      hour: 9,
      minute: 0,
    );
    expect(ScheduledTaskService.instance.tasks, hasLength(1));

    ScheduledTaskService.instance.tickForTest(DateTime(2026, 8, 10, 9, 1));
    expect(fired, 1);
    ScheduledTaskService.instance.tickForTest(DateTime(2026, 8, 10, 9, 30));
    expect(fired, 1); // 同一天不重复触发

    await ScheduledTaskService.instance.remove(t.id);
    expect(ScheduledTaskService.instance.tasks, isEmpty);
  });
}
