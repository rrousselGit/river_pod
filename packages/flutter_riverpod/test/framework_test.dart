import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:state_notifier/state_notifier.dart';
import 'package:mockito/mockito.dart';

void main() {
  testWidgets('context.refresh forces a provider to refresh', (tester) async {
    var future = Future.value(21);
    final provider = FutureProvider((ref) => future);

    await tester.pumpWidget(ProviderScope(child: Container()));

    final context = tester.element(find.byType(Container));

    await expectLater(context.read(provider.future), completion(21));

    future = Future.value(42);

    await expectLater(context.refresh(provider), completion(42));
  });

  testWidgets('ProviderScope allows specifying a ProviderContainer',
      (tester) async {
    final provider = FutureProvider((ref) async => 42);
    final container = ProviderContainer(overrides: [
      provider.overrideWithValue(const AsyncValue.data(42)),
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Container(),
      ),
    );

    final context = tester.element(find.byType(Container));

    expect(context.read(provider), const AsyncValue.data(42));
  });

  testWidgets('AlwaysAliveProviderBase.read(context) inside initState',
      (tester) async {
    final provider = Provider((_) => 42);
    int result;

    await tester.pumpWidget(
      ProviderScope(
        child: InitState(
          initState: (context) => result = context.read(provider),
        ),
      ),
    );

    expect(result, 42);
  });

  testWidgets('AlwaysAliveProviderBase.read(context) inside build',
      (tester) async {
    final provider = Provider((_) => 42);

    await tester.pumpWidget(
      ProviderScope(
        child: Builder(
          builder: (context) {
            // Allowed even if not a good practice. Will have a lint instead
            final value = context.read(provider);
            return Text(
              '$value',
              textDirection: TextDirection.ltr,
            );
          },
        ),
      ),
    );

    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('adding overrides throws', (tester) async {
    final provider = Provider((_) => 0);

    await tester.pumpWidget(ProviderScope(child: Container()));

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          provider.overrideWithProvider(Provider((_) => 1)),
        ],
        child: Container(),
      ),
    );

    expect(tester.takeException(), isAssertionError);
  });

  testWidgets('removing overrides is no-op', (tester) async {
    final provider = Provider((_) => 0);

    final consumer = Consumer((context, watch) {
      return Text(
        watch(provider).toString(),
        textDirection: TextDirection.ltr,
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          provider.overrideWithProvider(Provider((_) => 1)),
        ],
        child: consumer,
      ),
    );

    expect(find.text('1'), findsOneWidget);

    await tester.pumpWidget(ProviderScope(child: consumer));

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('overrive origin mismatch throws', (tester) async {
    final provider = Provider((_) => 0);
    final provider2 = Provider((_) => 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          provider.overrideWithProvider(Provider((_) => 1)),
        ],
        child: Container(),
      ),
    );

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          provider2.overrideWithProvider(Provider((_) => 1)),
        ],
        child: Container(),
      ),
    );

    expect(tester.takeException(), isAssertionError);
  });

  test('ProviderScope requires a child', () {
    expect(() => ProviderScope(child: null), throwsAssertionError);
  });

  testWidgets('throws if no ProviderScope found', (tester) async {
    final provider = Provider((_) => 'foo');

    await tester.pumpWidget(
      Consumer((context, watch) {
        watch(provider);
        return Container();
      }),
    );

    expect(
      tester.takeException(),
      isA<StateError>()
          .having((e) => e.message, 'message', 'No ProviderScope found'),
    );
  });

  testWidgets('providers can be overriden', (tester) async {
    final provider = Provider((_) => 'root');
    final provider2 = Provider((_) => 'root2');

    final builder = Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: <Widget>[
          Consumer((c, watch) => Text(watch(provider))),
          Consumer((c, watch) => Text(watch(provider2))),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        child: builder,
      ),
    );

    expect(find.text('root'), findsOneWidget);
    expect(find.text('root2'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          provider.overrideWithProvider(Provider((_) => 'override')),
        ],
        child: builder,
      ),
    );

    expect(find.text('root'), findsNothing);
    expect(find.text('override'), findsOneWidget);
    expect(find.text('root2'), findsOneWidget);
  });

  testWidgets('ProviderScope can be nested', (tester) async {
    final provider = Provider((_) => 'root');
    final provider2 = Provider((_) => 'root2');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          provider.overrideWithProvider(Provider((_) => 'rootoverride')),
        ],
        child: ProviderScope(
          child: Consumer((c, watch) {
            final first = watch(provider);
            final second = watch(provider2);
            return Text(
              '$first $second',
              textDirection: TextDirection.ltr,
            );
          }),
        ),
      ),
    );

    expect(find.text('root root2'), findsNothing);
    expect(find.text('rootoverride root2'), findsOneWidget);
  });

  testWidgets('ProviderScope debugFillProperties', (tester) async {
    final unnamed = Provider((_) => 0);
    final named = StateNotifierProvider((_) => Counter(), name: 'counter');
    final scopeKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        key: scopeKey,
        child: Consumer((c, watch) {
          final value = watch(unnamed);
          final count = watch(named.state);
          return Text(
            'value: $value count: $count',
            textDirection: TextDirection.ltr,
          );
        }),
      ),
    );

    expect(find.text('value: 0 count: 0'), findsOneWidget);

    expect(
      scopeKey.currentContext.toString(),
      equalsIgnoringHashCodes(
        'ProviderScope-[GlobalKey#00000]('
        'state: ProviderScopeState#00000, '
        'Provider<int>#00000: 0, '
        "counter: Instance of 'Counter', "
        'counter.state: 0)',
      ),
    );
  });

  testWidgets('UncontrolledProviderScope debugFillProperties', (tester) async {
    final unnamed = Provider((_) => 0);
    final named = StateNotifierProvider((_) => Counter(), name: 'counter');
    final container = ProviderContainer();
    final scopeKey = GlobalKey();

    container.read(unnamed);
    container.read(named.state);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        key: scopeKey,
        container: container,
        child: Container(),
      ),
    );

    expect(
      scopeKey.currentContext.toString(),
      equalsIgnoringHashCodes(
        'UncontrolledProviderScope-[GlobalKey#00000]('
        'Provider<int>#00000: 0, '
        "counter: Instance of 'Counter', "
        'counter.state: 0)',
      ),
    );
  });

  testWidgets('ProviderScope throws if ancestorOwner changed', (tester) async {
    final key = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        child: ProviderScope(
          key: key,
          child: Container(),
        ),
      ),
    );

    expect(find.byType(Container), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        child: ProviderScope(
          child: ProviderScope(
            key: key,
            child: Container(),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isUnsupportedError);
  });

  testWidgets('ProviderScope throws if ancestorOwner removed', (tester) async {
    final key = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        child: ProviderScope(
          key: key,
          child: Container(),
        ),
      ),
    );

    expect(find.byType(Container), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        key: key,
        child: Container(),
      ),
    );

    expect(tester.takeException(), isUnsupportedError);
  });
}

class Counter extends StateNotifier<int> {
  Counter() : super(0);
}

class MockCreateState extends Mock {
  void call();
}

class InitState extends StatefulWidget {
  const InitState({Key key, this.initState}) : super(key: key);

  final void Function(BuildContext context) initState;

  @override
  _InitStateState createState() => _InitStateState();
}

class _InitStateState extends State<InitState> {
  @override
  void initState() {
    super.initState();
    widget.initState(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
