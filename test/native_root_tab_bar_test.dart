import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('adaptive_platform_ui/native_tab_bar');

const _destinations = [
  AdaptiveNavigationDestination(icon: 'house', label: 'Home'),
  AdaptiveNavigationDestination(icon: 'bell', label: 'Alerts', badgeCount: 120),
];

void main() {
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  List<MethodCall> callsNamed(String method) =>
      calls.where((call) => call.method == method).toList();

  Future<void> sendFromNative(
    WidgetTester tester,
    String method,
    Object arguments,
  ) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
    await tester.pump();
  }

  Widget app({
    List<AdaptiveNavigationDestination> destinations = _destinations,
    int selectedIndex = 0,
    ValueChanged<int>? onTap,
    NativeTabAction? action,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: NativeRootTabBar(
          destinations: destinations,
          selectedIndex: selectedIndex,
          onTap: onTap ?? (_) {},
          action: action,
        ),
      ),
    );
  }

  testWidgets('sends the tabs once, with the badge and the action', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        selectedIndex: 1,
        action: NativeTabAction(sfSymbol: 'plus', label: 'Create', onPressed: () {}),
      ),
    );

    final setTabs = callsNamed('setTabs').single.arguments as Map;
    expect(setTabs['selectedIndex'], 1);
    final items = (setTabs['items'] as List).cast<Map>();
    expect(items.map((item) => item['id']), ['0', '1']);
    expect(items.map((item) => item['title']), ['Home', 'Alerts']);
    expect(items.map((item) => item['sfSymbol']), ['house', 'bell']);
    expect(items.map((item) => item['badge']), [null, '99+']);
    expect(setTabs['action'], {
      'id': 'action',
      'sfSymbol': 'plus',
      'title': 'Create',
    });
    expect(callsNamed('setHidden').single.arguments, {'hidden': false});
  });

  testWidgets('a rebuild with the same tabs sends nothing', (tester) async {
    await tester.pumpWidget(app());
    calls.clear();

    await tester.pumpWidget(app());

    expect(calls, isEmpty);
  });

  testWidgets('a new selected tab sends only the index', (tester) async {
    await tester.pumpWidget(app());
    calls.clear();

    await tester.pumpWidget(app(selectedIndex: 1));

    expect(calls.single.method, 'setSelectedIndex');
    expect(calls.single.arguments, {'index': 1});
  });

  testWidgets('a changed badge sends the tabs again', (tester) async {
    await tester.pumpWidget(app());
    calls.clear();

    await tester.pumpWidget(
      app(
        destinations: const [
          AdaptiveNavigationDestination(icon: 'house', label: 'Home'),
          AdaptiveNavigationDestination(icon: 'bell', label: 'Alerts', badgeCount: 3),
        ],
      ),
    );

    final items = (callsNamed('setTabs').single.arguments as Map)['items'] as List;
    expect((items[1] as Map)['badge'], '3');
    expect(callsNamed('setSelectedIndex'), isEmpty);
  });

  testWidgets('hides the bar while a page is pushed and shows it after pop', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    calls.clear();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Text('Detail')));
    await tester.pumpAndSettle();
    expect(callsNamed('setHidden').single.arguments, {'hidden': true});

    calls.clear();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(callsNamed('setHidden').single.arguments, {'hidden': false});
  });

  testWidgets('hides the bar while a dialog is open', (tester) async {
    await tester.pumpWidget(app());
    calls.clear();

    showDialog<void>(
      context: tester.element(find.byType(Scaffold)),
      builder: (_) => const Text('Dialog'),
    );
    await tester.pumpAndSettle();

    expect(callsNamed('setHidden').single.arguments, {'hidden': true});
  });

  testWidgets('a tapped tab calls onTap and is not sent back', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(app(onTap: tapped.add));
    calls.clear();

    await sendFromNative(tester, 'onTabSelected', {'index': 1});
    await tester.pumpWidget(app(selectedIndex: 1, onTap: tapped.add));

    expect(tapped, [1]);
    expect(calls, isEmpty);
  });

  testWidgets('the action runs its own callback, not onTap', (tester) async {
    final tapped = <int>[];
    var actionCount = 0;
    await tester.pumpWidget(
      app(
        onTap: tapped.add,
        action: NativeTabAction(
          sfSymbol: 'plus',
          label: 'Create',
          onPressed: () => actionCount++,
        ),
      ),
    );

    await sendFromNative(tester, 'onAction', {'id': 'action'});

    expect(actionCount, 1);
    expect(tapped, isEmpty);
  });

  testWidgets('going away hides the bar', (tester) async {
    await tester.pumpWidget(app());
    calls.clear();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(callsNamed('setHidden').single.arguments, {'hidden': true});
  });
}
