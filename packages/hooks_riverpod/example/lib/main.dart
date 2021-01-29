import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

void main() {
  runApp(
    /// [MyApp] is wrapped in a [ProviderScope].
    /// This widget is where the state of most of our providers will be stored.
    /// This replaces `MultiProvider` if you've used `provider` before.
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

/// A provider that creates and listen to a [StateNotifier].
///
/// Providers are declared as global variables.
/// This does not hinder testability, as the state of a provider is instead
/// stored inside a [ProviderScope].
final counterProvider = StateNotifierProvider<Counter>((_) => Counter());

/// A simple [StateNotifier] that implements a counter.
///
/// It doesn't have to be a [StateNotifier], and could be anything else such as:
/// - [ChangeNotifier], with [ChangeNotifierProvider]
/// - [Stream], with [StreamProvider]
/// ...
class Counter extends StateNotifier<int> {
  Counter() : super(0);

  void increment() => state++;
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends HookWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final count = useProvider(counterProvider.state);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riverpod counter example'),
      ),
      body: Center(
        child: Text(
          '$count',
          style: Theme.of(context).textTheme.headline4,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.read(counterProvider).increment(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
