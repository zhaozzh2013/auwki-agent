import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/task_queue_service.dart';

void main() {
  late Directory tmp;
  late File taskFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('auwki_task_test');
    taskFile = File('${tmp.path}/tasks.json');
    TaskQueueService.debugFile = taskFile;
  });

  tearDown(() async {
    await TaskQueueService.instance.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('A04: task lifecycle start -> progress -> finished', () async {
    final t = await TaskQueueService.instance.start('c1', '写一个贪吃蛇');
    expect(t.status, TaskStatus.running);

    await TaskQueueService.instance.updateProgress(t.id, 'listfiles(.)');
    expect(
      TaskQueueService.instance.byId(t.id)?.progress,
      'listfiles(.)',
    );

    await TaskQueueService.instance.markFinished(t.id);
    expect(TaskQueueService.instance.byId(t.id)?.status, TaskStatus.finished);
  });

  test('A05: cancel saves checkpoint and resume is consumable', () async {
    final t = await TaskQueueService.instance.start('c1', '任务');
    await TaskQueueService.instance.cancelTask(t.id, checkpoint: {
      'history': [
        {'role': 'user', 'content': 'hi'},
      ],
      'turn': 2,
    });
    final task = TaskQueueService.instance.byId(t.id)!;
    expect(task.status, TaskStatus.cancelled);
    expect(task.checkpoint, isNotNull);

    TaskQueueService.instance.requestResume(t.id);
    expect(TaskQueueService.instance.consumeResume('other'), isNull);
    final checkpoint = TaskQueueService.instance.consumeResume('c1');
    expect(checkpoint, isNotNull);
    expect(checkpoint!['turn'], 2);
  });

  test('A04: tasks persist across reload', () async {
    final t = await TaskQueueService.instance.start('c1', '持久化任务');
    await TaskQueueService.instance.markFinished(t.id);

    await TaskQueueService.instance.resetForTest();
    TaskQueueService.debugFile = taskFile;
    await TaskQueueService.instance.reloadForTest();
    final reloaded = TaskQueueService.instance.tasks;
    expect(reloaded, hasLength(1));
    expect(reloaded.first.id, t.id);
    expect(reloaded.first.status, TaskStatus.finished);
  });
}
