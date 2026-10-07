import 'dart:async';

import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/design_page_read_dispatcher.dart';
import 'package:energylens_mobile/features/design/tips_domain_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-1111-1111-111111111111';
const homeB = '22222222-2222-2222-2222-222222222222';

class RecordingAdapters implements DesignContextAdapters {
  final calls = <(String, TipsPage)>[];
  int clears = 0;
  Completer<TipsDomainSnapshot?>? pending;

  @override
  void clear() => clears++;

  @override
  Future<TipsDomainSnapshot?> tips(String homeId, TipsPage page) {
    calls.add((homeId, page));
    return pending?.future ?? Future.value(_tips(homeId, page));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TipsDomainSnapshot _tips(String homeId, TipsPage page) => TipsDomainSnapshot(
  homeId: homeId,
  page: page,
  programs: null,
  recommendations: const [],
  operatingEstimates: const [],
  usageFactsByAppliance: const {},
  factsIncomplete: false,
);

VerifiedDesignContext _context(
  String homeId, {
  DesignContextMode mode = DesignContextMode.household,
}) => VerifiedDesignContext(accountId: 'account-a', homeId: homeId, mode: mode);

void main() {
  test('reads only eligible pages in a verified context', () async {
    final adapters = RecordingAdapters();
    final coordinator = DesignContextCoordinator(adapters);
    final dispatcher = DesignPageReadDispatcher(coordinator);
    await dispatcher.load('perks_tips');
    expect(adapters.calls, isEmpty);
    coordinator.useVerifiedContext(_context(homeA));
    await dispatcher.load('tips_knowledge');
    expect(adapters.calls, isEmpty);
    await dispatcher.load('perks_tips');
    expect(adapters.calls, [(homeA, TipsPage.perksTips)]);
    expect(dispatcher.latestRead?.page, 'perks_tips');
    expect(dispatcher.latestRead?.homeId, homeA);
    coordinator.useVerifiedContext(
      _context(homeA, mode: DesignContextMode.sample),
    );
    expect(dispatcher.latestRead, isNull);
    await dispatcher.load('perks_tips');
    expect(adapters.calls.length, 1);
  });

  test('navigation drops a late result and a late error', () async {
    final adapters = RecordingAdapters();
    final coordinator = DesignContextCoordinator(adapters)
      ..useVerifiedContext(_context(homeA));
    final dispatcher = DesignPageReadDispatcher(coordinator);
    final first = Completer<TipsDomainSnapshot?>();
    adapters.pending = first;
    final staleResult = dispatcher.load('perks_tips');
    await dispatcher.load('tips_knowledge');
    first.complete(_tips(homeA, TipsPage.perksTips));
    await staleResult;
    expect(dispatcher.latestRead, isNull);
    expect(dispatcher.latestError, isNull);

    final second = Completer<TipsDomainSnapshot?>();
    adapters.pending = second;
    final staleError = dispatcher.load('perks_tips');
    await dispatcher.load('tips_knowledge');
    second.completeError(StateError('old page'));
    await staleError;
    expect(dispatcher.latestError, isNull);
  });

  test('home switch, sign-out, and disposal hide previous reads', () async {
    final adapters = RecordingAdapters();
    final coordinator = DesignContextCoordinator(adapters)
      ..useVerifiedContext(_context(homeA));
    final dispatcher = DesignPageReadDispatcher(coordinator);
    await dispatcher.load('perks_tips');
    expect(dispatcher.latestRead?.homeId, homeA);
    coordinator.useVerifiedContext(_context(homeB));
    expect(dispatcher.latestRead, isNull);

    final pending = Completer<TipsDomainSnapshot?>();
    adapters.pending = pending;
    final old = dispatcher.load('perks_tips');
    coordinator.signOut();
    pending.complete(_tips(homeB, TipsPage.perksTips));
    await old;
    expect(dispatcher.latestRead, isNull);
    dispatcher.dispose();
    coordinator.useVerifiedContext(_context(homeA));
    await dispatcher.load('perks_tips');
    expect(adapters.calls.length, 2);
    expect(dispatcher.latestRead, isNull);
  });

  test(
    'sign-out and return to the same context cannot restore cached data',
    () async {
      final adapters = RecordingAdapters();
      final coordinator = DesignContextCoordinator(adapters);
      final context = _context(homeA);
      coordinator.useVerifiedContext(context);
      final dispatcher = DesignPageReadDispatcher(coordinator);
      await dispatcher.load('perks_tips');
      expect(dispatcher.latestRead?.homeId, homeA);

      coordinator.signOut();
      expect(dispatcher.latestRead, isNull);
      coordinator.useVerifiedContext(context);
      expect(dispatcher.latestRead, isNull);
      expect(adapters.clears, 3);
      await dispatcher.load('perks_tips');
      expect(dispatcher.latestRead?.homeId, homeA);
    },
  );

  test('same context reused after a home switch hides prior error', () async {
    final adapters = RecordingAdapters();
    final coordinator = DesignContextCoordinator(adapters);
    final firstContext = _context(homeA);
    coordinator.useVerifiedContext(firstContext);
    final dispatcher = DesignPageReadDispatcher(coordinator);
    final pending = Completer<TipsDomainSnapshot?>();
    adapters.pending = pending;
    final failed = dispatcher.load('perks_tips');
    pending.completeError(StateError('failed read'));
    await failed;
    expect(dispatcher.latestError, isA<StateError>());

    coordinator.useVerifiedContext(_context(homeB));
    coordinator.useVerifiedContext(firstContext);
    expect(dispatcher.latestError, isNull);
    expect(dispatcher.latestRead, isNull);
    expect(adapters.clears, 3);
  });

  test(
    'late result after sign-out and reselection of same object is discarded',
    () async {
      final adapters = RecordingAdapters();
      final coordinator = DesignContextCoordinator(adapters);
      final context = _context(homeA);
      coordinator.useVerifiedContext(context);
      final dispatcher = DesignPageReadDispatcher(coordinator);
      final pending = Completer<TipsDomainSnapshot?>();
      adapters.pending = pending;
      final old = dispatcher.load('perks_tips');
      coordinator.signOut();
      coordinator.useVerifiedContext(context);
      pending.complete(_tips(homeA, TipsPage.perksTips));
      await old;
      expect(dispatcher.latestRead, isNull);
      expect(dispatcher.latestError, isNull);
    },
  );
}
