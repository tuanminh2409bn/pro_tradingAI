import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/core/widgets/sync_gate_modal.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    Widget gate, {
    String language = 'en',
  }) => tester.pumpWidget(
    BlocProvider(
      create: (_) => LocaleCubit()..setLanguage(language),
      child: MaterialApp(home: Scaffold(body: gate)),
    ),
  );

  Widget preview({FocusNode? focusNode, required VoidCallback onExport}) =>
      Column(
        children: [
          const Text('Private trade preview'),
          ElevatedButton(
            key: const ValueKey('private-export'),
            focusNode: focusNode,
            onPressed: onExport,
            child: const Text('Private CSV export'),
          ),
        ],
      );

  testWidgets('locked preview is absent from assistive semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await show(
        tester,
        BrokerLinkGateView(
          linked: false,
          onConnect: () {},
          child: preview(onExport: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Private trade preview'), findsNothing);
      expect(find.bySemanticsLabel('Private CSV export'), findsNothing);
      expect(find.bySemanticsLabel('CONNECT NOW'), findsOneWidget);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('locked preview cannot receive focus or keyboard execution', (
    tester,
  ) async {
    var exports = 0;
    var connections = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await show(
      tester,
      BrokerLinkGateView(
        linked: false,
        onConnect: () => connections++,
        child: preview(focusNode: focus, onExport: () => exports++),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(exports, 0);
    await tester.tap(
      find.byKey(const ValueKey('private-export')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(exports, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(connections, 1);
    await tester.tap(find.text('CONNECT NOW'));
    await tester.pump();
    expect(connections, 2);
  });

  testWidgets('anonymous gate never opens preview', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await show(
        tester,
        BrokerLinkGate(
          userId: null,
          onConnect: () {},
          child: preview(onExport: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('JOURNAL LOCKED'), findsOneWidget);
      expect(find.bySemanticsLabel('Private CSV export'), findsNothing);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('empty owner stays locked without constructing Firestore', (
    tester,
  ) async {
    for (final uid in ['', ' ']) {
      await show(
        tester,
        BrokerLinkGate(
          userId: uid,
          onConnect: () {},
          child: preview(onExport: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('JOURNAL LOCKED'), findsOneWidget);
    }
  });

  testWidgets('Vietnamese gate fits 390 px and connection stays operable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var connections = 0;
    await show(
      tester,
      BrokerLinkGateView(
        linked: false,
        onConnect: () => connections++,
        child: preview(onExport: () {}),
      ),
      language: 'vi',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('JOURNAL ĐÃ KHÓA'), findsOneWidget);
    await tester.tap(find.text('KẾT NỐI NGAY'));
    await tester.pump();
    expect(connections, 1);
  });

  testWidgets(
    'verified link permits pointer and keyboard; relock clears focus',
    (tester) async {
      var exports = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      Widget gate(bool linked) => BrokerLinkGateView(
        linked: linked,
        onConnect: () {},
        child: preview(focusNode: focus, onExport: () => exports++),
      );
      await show(tester, gate(true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('private-export')));
      await tester.pump();
      expect(exports, 1);
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(exports, 2);
      await show(tester, gate(false));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(exports, 2);
    },
  );
}
