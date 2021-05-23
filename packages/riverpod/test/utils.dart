import 'dart:async';

import 'package:mockito/mockito.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

class Counter extends StateNotifier<int> {
  Counter() : super(0);

  void increment() => state++;
}

ProviderContainer createContainer({
  ProviderContainer? parent,
  List<Override> overrides = const [],
  List<ProviderObserver>? observers,
}) {
  final container = ProviderContainer(
    parent: parent,
    overrides: overrides,
    observers: observers,
  );
  addTearDown(container.dispose);
  return container;
}

List<Object> errorsOf(void Function() cb) {
  final errors = <Object>[];
  runZonedGuarded(cb, (err, _) => errors.add(err));
  return [...errors];
}

// class MayHaveChangedMock<T> extends Mock {
//   void call(ProviderSubscription<T>? sub);
// }

// class DidChangedMock<T> extends Mock {
//   void call(ProviderSubscription<T>? sub);
// }

class OnBuildMock extends Mock {
  void call();
}

class OnDisposeMock extends Mock {
  void call();
}

class Listener<T> extends Mock {
  void call(T value);
}

typedef VerifyOnly = VerificationResult Function<T>(
  Mock mock,
  T matchingInvocations,
);

/// Syntax sugar for:
///
/// ```dart
/// verify(mock()).called(1);
/// verifyNoMoreInteractions(mock);
/// ```
VerifyOnly get verifyOnly {
  final verification = verify;

  return <T>(mock, invocation) {
    final result = verification(invocation);
    result.called(1);
    verifyNoMoreInteractions(mock);
    return result;
  };
}

// Copied from Flutter
/// Asserts that two [String]s are equal after normalizing likely hash codes.
///
/// A `#` followed by 5 hexadecimal digits is assumed to be a short hash code
/// and is normalized to #00000.
Matcher equalsIgnoringHashCodes(String value) {
  return _EqualsIgnoringHashCodes(value);
}

class _EqualsIgnoringHashCodes extends Matcher {
  _EqualsIgnoringHashCodes(String v) : _value = _normalize(v);

  final String _value;

  static final Object _mismatchedValueKey = Object();

  static String _normalize(String s) {
    return s.replaceAll(RegExp('#[0-9a-fA-F]{5}'), '#00000');
  }

  @override
  bool matches(Object? object, Map<Object?, Object?> matchState) {
    final description = _normalize(object! as String);
    if (_value != description) {
      matchState[_mismatchedValueKey] = description;
      return false;
    }
    return true;
  }

  @override
  Description describe(Description description) {
    return description.add('multi line description equals $_value');
  }

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) {
    if (matchState.containsKey(_mismatchedValueKey)) {
      final actualValue = matchState[_mismatchedValueKey]! as String;
      // Leading whitespace is added so that lines in the multiline
      // description returned by addDescriptionOf are all indented equally
      // which makes the output easier to read for this case.
      return mismatchDescription
          .add('expected normalized value\n  ')
          .addDescriptionOf(_value)
          .add('\nbut got\n  ')
          .addDescriptionOf(actualValue);
    }
    return mismatchDescription;
  }
}

class ObserverMock extends Mock implements ProviderObserver {
  @override
  void didDisposeProvider(ProviderBase<Object?>? provider) {
    super.noSuchMethod(
      Invocation.method(#didDisposeProvider, [provider]),
    );
  }

  @override
  void didAddProvider(ProviderBase<Object?>? provider, Object? value) {
    super.noSuchMethod(
      Invocation.method(#didAddProvider, [provider, value]),
    );
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?>? provider,
    Object? previousValue,
    Object? newValue,
  ) {
    super.noSuchMethod(
      Invocation.method(#didUpdateProvider, [provider, newValue]),
    );
  }
}

// can subclass ProviderObserver without implementing all life-cycles
class CustomObserver extends ProviderObserver {}
