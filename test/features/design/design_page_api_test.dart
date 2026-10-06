import 'dart:convert';

import 'package:energylens_mobile/features/design/design_page_api.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport implements DesignPageTransport {
  _Transport(this.response);
  final String response;
  String? requestedPath;

  @override
  Future<String> get(String path) async {
    requestedPath = path;
    return response;
  }
}

Map<String, dynamic> _body({
  String home = 'home_1',
  String page = 'dashboard',
}) => {
  'schema_revision': 'mobile_design_page_v1',
  'home_id': home,
  'page': page,
  'data_mode': 'sample',
  'fixture_revision': designFixtureRevision,
  'snapshot_id': 'sample_snapshot_1',
  'generated_at': '2026-10-06T20:00:00Z',
  'as_of': '2026-10-06T20:00:00Z',
  'timezone': 'America/Chicago',
  'period': {
    'start_local': '2026-10-06T00:00:00',
    'end_exclusive_local': '2026-10-07T00:00:00',
  },
  'scope': 'page_specific_sample',
  'availability': 'available',
  'evidence_basis': 'page_fixture',
  'actions_enabled': false,
  'fixture': {
    'fixture_revision': designFixtureRevision,
    'page': page,
    'ordered_text_segments': [
      {
        'path': '/html[1]/body[1]/main[1]/span[1]',
        'text': r'$6.96',
        'hidden_initially': false,
        'icon_glyph': false,
      },
    ],
    'controls': [],
    'media': [],
    'initial_states': [],
  },
};

void main() {
  test(
    'repository uses owner-scoped path and parses exact fixture text',
    () async {
      final transport = _Transport(jsonEncode(_body()));
      final snapshot = await DesignPageRepository(transport)
          .fetch('home_1', 'dashboard');
      expect(
        transport.requestedPath,
        '/v1/homes/home_1/design-pages/dashboard',
      );
      expect(snapshot.textSegments.single.text, r'$6.96');
      expect(snapshot.page, 'dashboard');
    },
  );

  test(
    'repository rejects unknown route, wrong home, and missing data',
    () async {
      final transport = _Transport(jsonEncode(_body(home: 'other_home')));
      final repository = DesignPageRepository(transport);
      await expectLater(
        repository.fetch('home_1', 'dashboard'),
        throwsFormatException,
      );
      expect(
        transport.requestedPath,
        '/v1/homes/home_1/design-pages/dashboard',
      );
      await expectLater(
        repository.fetch('home_1', 'unknown'),
        throwsArgumentError,
      );
      expect(
        transport.requestedPath,
        '/v1/homes/home_1/design-pages/dashboard',
      );
      final incomplete = _body()..remove('fixture');
      await expectLater(
        DesignPageRepository(_Transport(jsonEncode(incomplete)))
            .fetch('home_1', 'dashboard'),
        throwsFormatException,
      );
    },
  );

  test(
    'household mode cannot use the sample fixture parser or fallback',
    () async {
      final household = _body()..['data_mode'] = 'household';
      await expectLater(
        DesignPageRepository(_Transport(jsonEncode(household)))
            .fetch('home_1', 'dashboard'),
        throwsFormatException,
      );
    },
  );

  test('nullable time context follows the finalized sample contract', () async {
    final body = _body()
      ..['generated_at'] = null
      ..['as_of'] = null
      ..['timezone'] = null
      ..['period'] = null;
    final snapshot = await DesignPageRepository(_Transport(jsonEncode(body)))
        .fetch('home_1', 'dashboard');
    expect(snapshot.generatedAt, isNull);
    expect(snapshot.asOf, isNull);
    expect(snapshot.timezone, isNull);
    expect(snapshot.period, isNull);
    body['generated_at'] = 'invalid';
    await expectLater(
      DesignPageRepository(_Transport(jsonEncode(body)))
          .fetch('home_1', 'dashboard'),
      throwsFormatException,
    );
  });

  test('generation gate rejects old page and home responses', () {
    final response = DesignPageSnapshot.fromJson(
      _body(),
      expectedHomeId: 'home_1',
      expectedPage: 'dashboard',
    );
    final gate = DesignPageRequestGate();
    final first = gate.select('home_1', 'dashboard');
    expect(gate.accepts(first, response), isTrue);
    gate.select('home_1', 'devices');
    expect(gate.accepts(first, response), isFalse);
    final second = gate.select('home_1', 'dashboard');
    expect(gate.accepts(second, response), isTrue);
    gate.select('home_2', 'dashboard');
    expect(gate.accepts(second, response), isFalse);
    gate.clear();
    expect(gate.accepts(second, response), isFalse);
  });

  test('bridge validates version, page, home, action and owned entity', () {
    String message(Map<String, dynamic> changes) => jsonEncode({
      'version': 1,
      'home_id': 'home_1',
      'page': 'dashboard',
      'action': 'navigate',
      'target_page': 'devices',
      ...changes,
    });
    DesignBridgeMessage? parse(String raw) => DesignBridgeMessage.parse(
      raw,
      expectedHomeId: 'home_1',
      expectedPage: 'dashboard',
      ownedEntityIds: {'device_1'},
    );
    expect(parse(message({}))?.targetPage, 'devices');
    expect(parse(message({'home_id': 'home_2'})), isNull);
    expect(parse(message({'page': 'settings'})), isNull);
    expect(parse(message({'version': 2})), isNull);
    expect(parse(message({'action': 'switch_plug'})), isNull);
    expect(parse(message({'target_page': 'unknown'})), isNull);
    expect(parse(message({'entity_id': 'foreign_device'})), isNull);
    expect(parse(message({'unexpected': true})), isNull);
    expect(parse('x' * 4097), isNull);
  });

  test(
    'text binding payload preserves literal text and rejects duplicate IDs',
    () {
      final payload = encodeDesignTextBindings([
        const DesignTextBinding('daily_cost', '<script>alert(1)</script>'),
      ]);
      expect(
        (jsonDecode(payload) as Map<String, dynamic>)['bindings'][0]['text'],
        '<script>alert(1)</script>',
      );
      expect(
        () => encodeDesignTextBindings([
          const DesignTextBinding('daily_cost', 'one'),
          const DesignTextBinding('daily_cost', 'two'),
        ]),
        throwsArgumentError,
      );
    },
  );
}
