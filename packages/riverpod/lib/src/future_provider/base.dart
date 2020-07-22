part of '../future_provider.dart';

/// {@macro riverpod.futureprovider}
class FutureProvider<T>
    extends AlwaysAliveProviderBase<Future<T>, AsyncValue<T>> with _FutureProviderMixin<T>{
  /// {@macro riverpod.futureprovider}
  FutureProvider(
    Create<Future<T>, ProviderReference> create, {
    String name,
  }) : super(create, name);

  /// {@macro riverpod.family}
  static const family = FutureProviderFamilyBuilder();

  /// {@macro riverpod.autoDispose}
  static const autoDispose = AutoDisposeFutureProviderBuilder();

  AlwaysAliveProviderBase<Future<T>, Future<T>> _future;
  AlwaysAliveProviderBase<Future<T>, Future<T>> get future {
    return _future ??= CreatedProvider(
      this,
      name: name == null ? null : '$name.future',
    );
  }

  @override
  _FutureProviderState<T> createState() => _FutureProviderState();
}

class _FutureProviderState<T> = ProviderStateBase<Future<T>, AsyncValue<T>>
    with _FutureProviderStateMixin<T>;

class FutureProviderFamily<T, A> extends Family<Future<T>, AsyncValue<T>, A,
    ProviderReference, FutureProvider<T>> {
  FutureProviderFamily(
    Future<T> Function(ProviderReference ref, A a) create, {
    String name,
  }) : super(create, name);

  @override
  FutureProvider<T> create(
    A value,
    Future<T> Function(ProviderReference ref, A param) builder,
  ) {
    return FutureProvider((ref) => builder(ref, value), name: name);
  }
}