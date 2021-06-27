part of '../future_provider.dart';

/// {@macro riverpod.providerrefbase}
/// - [ProviderRef.state], the value currently exposed by this providers.
typedef AutoDisposeFutureProviderRef<State>
    = AutoDisposeProviderRef<AsyncValue<State>>;

/// {@macro riverpod.futureprovider}
@sealed
class AutoDisposeFutureProvider<State>
    extends AutoDisposeProviderBase<AsyncValue<State>>
    with AutoDisposeProviderOverridesMixin<AsyncValue<State>> {
  /// {@macro riverpod.futureprovider}
  AutoDisposeFutureProvider(this._create, {String? name}) : super(name);

  /// {@macro riverpod.family}
  static const family = AutoDisposeFutureProviderFamilyBuilder();

  final Create<Future<State>, AutoDisposeFutureProviderRef<State>> _create;

  /// {@macro riverpod.futureprovider.future}
  late final AutoDisposeProviderBase<Future<State>> future =
      AutoDisposeAsyncValueAsFutureProvider(this, modifierName(name, 'future'));

  @override
  AsyncValue<State> create(
    AutoDisposeFutureProviderRef<State> ref,
  ) {
    return _listenFuture(() => _create(ref), ref);
  }

  @override
  bool recreateShouldNotify(
    AsyncValue<State> previousState,
    AsyncValue<State> newState,
  ) {
    return true;
  }

  @override
  SetupOverride get setupOverride => (setup) {
        setup(origin: this, override: this);
        setup(origin: future, override: future);
      };

  @override
  Override overrideWithProvider(
    AutoDisposeProviderBase<AsyncValue<State>> provider,
  ) {
    return ProviderOverride((setup) {
      setup(origin: future, override: this);
      setup(origin: this, override: provider);
    });
  }

  @override
  Override overrideWithValue(AsyncValue<State> value) {
    return ProviderOverride((setup) {
      setup(origin: future, override: future);
      setup(origin: this, override: ValueProvider<AsyncValue<State>>(value));
    });
  }

  @override
  AutoDisposeProviderElement<AsyncValue<State>> createElement() {
    return AutoDisposeProviderElement(this);
  }
}

/// {@template riverpod.futureprovider.family}
/// A class that allows building a [AutoDisposeFutureProvider] from an external parameter.
/// {@endtemplate}
@sealed
class AutoDisposeFutureProviderFamily<State, Arg>
    extends Family<AsyncValue<State>, Arg, AutoDisposeFutureProvider<State>> {
  /// {@macro riverpod.futureprovider.family}
  AutoDisposeFutureProviderFamily(this._create, {String? name}) : super(name);

  final FamilyCreate<Future<State>, AutoDisposeFutureProviderRef<State>, Arg>
      _create;

  @override
  AutoDisposeFutureProvider<State> create(Arg argument) {
    return AutoDisposeFutureProvider(
      (ref) => _create(ref, argument),
      name: name,
    );
  }
}
