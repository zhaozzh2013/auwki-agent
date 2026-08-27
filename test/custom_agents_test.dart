import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/agent.dart';

void main() {
  test('A16: agentFromPlanItemWithCustom uses custom agent', () {
    final item = FlagshipPlanItem(
      agentId: 'qa',
      focus: 'review',
      title: 'QA',
      instruction: 'test only',
    );
    final agent = AgentRunner.agentFromPlanItemWithCustom(item, [
      {'id': 'qa', 'name': 'QA', 'instruction': 'test only'},
    ]);
    expect(agent.id, 'qa');
    expect(agent.title, 'QA');
    expect(agent.instruction, 'test only');
  });

  test('A16: falls back to built-in agents', () {
    final item = FlagshipPlanItem(agentId: 'prometheus', focus: 'plan');
    final agent = AgentRunner.agentFromPlanItemWithCustom(item, const []);
    expect(agent.id, 'prometheus');
    expect(agent.title, 'Prometheus');
  });

  test('A16: coordinator prompt includes custom agent ids', () async {
    String? captured;
    await AgentRunner.planFlagshipSession(
      chat: (system, messages) async* {
        captured = system;
        yield '{"coordinatorNote":"n","complete":true,"items":[]}';
      },
      history: const [],
      isEnglish: true,
      customAgents: [
        {'id': 'qa', 'name': 'QA', 'instruction': 'test only'},
      ],
    );
    expect(captured, isNotNull);
    expect(captured, contains('qa'));
  });
}
