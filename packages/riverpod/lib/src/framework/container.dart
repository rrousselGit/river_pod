part of '../framework.dart';

void _runGuarded(void Function() cb) {
  try {
    cb();
  } catch (err, stack) {
    Zone.current.handleUncaughtError(err, stack);
  }
}

void _runUnaryGuarded<T, Res>(Res Function(T) cb, T value) {
  try {
    cb(value);
  } catch (err, stack) {
    Zone.current.handleUncaughtError(err, stack);
  }
}

void _runBinaryGuarded<A, B>(void Function(A, B) cb, A value, B value2) {
  try {
    cb(value, value2);
  } catch (err, stack) {
    Zone.current.handleUncaughtError(err, stack);
  }
}

ProviderBase? _circularDependencyLock;

void _defaultVsync(void Function() task) {
  Future(task);
}

int _debugNextId = 0;

class _FamilyOverrideRef {
  _FamilyOverrideRef(this.override, this.container);

  FamilyOverride override;
  final ProviderContainer container;
}

/// An object that contains a [ProviderElementBase].
///
/// This object is used to implement the scoping mechanism of providers,
/// by allowing a [ProviderContainer] to "inherit" the [_StateReader]s from
/// its ancestor, while preserving the "mount providers on demand" logic.
class _StateReader {
  _StateReader({
    required this.origin,
    required this.override,
    required this.container,
    required this.isOverride,
  });

  final ProviderBase origin;
  ProviderBase override;
  final ProviderContainer container;
  final bool isOverride;

  ProviderElementBase? _element;

  ProviderElementBase getElement() => _element ??= _create();

  ProviderElementBase _create() {
    if (origin == _circularDependencyLock) {
      throw CircularDependencyError._();
    }
    _circularDependencyLock ??= origin;
    try {
      final element = override.createElement()
        .._provider = override
        .._origin = origin
        .._container = container
        ..mount();

      for (final observer in container._observers) {
        _runGuarded(
          () => observer.didAddProvider(origin, element._state, container),
        );
      }
      return element;
    } finally {
      if (_circularDependencyLock == origin) {
        _circularDependencyLock = null;
      }
    }
  }
}

/// {@template riverpod.providercontainer}
/// An object that stores the state of the providers and allows overriding the
/// behavior of a specific provider.
///
/// If you are using Flutter, you do not need to care about this object
/// (outside of testing), as it is implicitly created for you by `ProviderScope`.
/// {@endtemplate}
@sealed
class ProviderContainer {
  /// {@macro riverpod.providercontainer}
  ProviderContainer({
    ProviderContainer? parent,
    List<Override> overrides = const [],
    List<ProviderObserver>? observers,
  })  : depth = parent == null ? 0 : parent.depth + 1,
        _parent = parent,
        _observers = [
          ...?observers,
          if (parent != null) ...parent._observers,
        ],
        _root = parent?._root ?? parent {
    assert(() {
      _debugId = '${_debugNextId++}';
      RiverpodBinding.debugInstance.containers = {
        ...RiverpodBinding.debugInstance.containers,
        _debugId: this,
      };
      return true;
    }(), '');

    if (parent != null) {
      // TODO ProviderObserver on scoped providers uses scoped observers + ancestor observers
      parent._children.add(this);
      _overrideForFamily.addAll(parent._overrideForFamily);
      _stateReaders.addAll(parent._stateReaders);
    }

    for (final override in overrides) {
      if (override is ProviderOverride) {
        void setupOverride({
          required ProviderBase override,
          required ProviderBase origin,
        }) {
          assert(
            !_overrideForProvider.containsKey(origin),
            'The provider $origin is already overriden',
          );
          _overrideForProvider[origin] = override;
          _stateReaders[origin] = _StateReader(
            origin: origin,
            override: override,
            container: this,
            isOverride: true,
          );
        }

        override.setupOverride(setupOverride);
      } else if (override is FamilyOverride) {
        _overrideForFamily[override.overridenFamily] = _FamilyOverrideRef(
          override,
          this,
        );
      }
    }
  }

  /// A function that controls the refresh rate of providers.
  ///
  /// Defaults to refreshing providers at the end of the next event-loop.
  void Function(void Function() task) get vsync {
    return vsyncOverride ?? _defaultVsync;
  }

  /// A way to override [vsync], used by Flutter to synchronize a container
  /// with the widget tree.
  void Function(void Function() task)? vsyncOverride;

  /// The object that handles when providers are refreshed and disposed.
  late final _ProviderScheduler _scheduler =
      _parent?._scheduler ?? _ProviderScheduler(vsync);

  late final String _debugId;

  /// How deep this [ProviderContainer] is in the graph of containers.
  ///
  /// Starts at 0.
  final int depth;

  /// A unique ID for this object, used by the devtool to differentiate two [ProviderContainer].
  ///
  /// Should not be used.
  @visibleForTesting
  String get debugId {
    String? id;
    assert(() {
      id = _debugId;
      return true;
    }(), '');

    return id!;
  }

  final ProviderContainer? _root;
  final ProviderContainer? _parent;

  final _children = <ProviderContainer>[];

  /// All the containers that have this container as `parent`.
  ///
  /// Do not use in production
  List<ProviderContainer> get debugChildren => UnmodifiableListView(_children);

  final _overrideForProvider = HashMap<ProviderBase, ProviderBase>();
  final _overrideForFamily = HashMap<Family, _FamilyOverrideRef>();
  final _stateReaders = HashMap<ProviderBase, _StateReader>();

  // /// A function that calls its callback at the end of the current "frame".
  // ///
  // /// This is exposed so that
  // ///
  // /// Defaults to wraping the callback in a [Future].
  // void Function(void Function()) addPostFrameCallback = (cb) => Future(cb);

  /// Awaits for providers to rebuild/be disposed and for listeners to be notified.
  Future<void> pump() async {
    return _scheduler.pendingFuture;
  }

  final List<ProviderObserver> _observers;

  /// A debug utility used by `flutter_riverpod`/`hooks_riverpod` to check
  /// if it is safe to modify a provider.
  ///
  /// This corresponds to all the widgets that a [Provider] is associated with.
  void Function()? debugCanModifyProviders;

  /// Whether [dispose] was called or not.
  ///
  /// This disables the different methods of [ProviderContainer], resulting in
  /// a [StateError] when attempting to use them.
  bool _disposed = false;

  /// Reads a provider without listening to it and returns the currently
  /// exposed value.
  ///
  /// ```dart
  /// final greetingProvider = Provider((_) => 'Hello world');
  ///
  /// void main() {
  ///   final container = ProviderContainer();
  ///
  ///   print(container.read(greetingProvider)); // Hello World
  /// }
  /// ```
  Result read<Result>(
    ProviderBase<Result> provider,
  ) {
    final element = readProviderElement(provider);
    element.flush();

    // In case `read` was called on a provider that has no listener
    element.mayNeedDispose();

    return element.getExposedValue();
  }

  /// Subscribe to this provider.
  ///
  /// See also:
  ///
  /// - [ProviderSubscription], which allows reading the current value and
  ///   closing the subscription.
  /// - [ProviderRefBase.watch], which is an easier way for providers to listen
  ///   to another provider.
  ProviderSubscription<State> listen<State>(
    ProviderListenable<State> provider,
    void Function(State value) listener, {
    bool fireImmediately = false,
  }) {
    if (provider is _ProviderSelector<Object?, State>) {
      return provider.listen(this, listener, fireImmediately: fireImmediately);
    }

    final element = readProviderElement(provider as ProviderBase<State>);

    return element.addListener(
      provider,
      listener,
      fireImmediately: fireImmediately,
    );
  }

  /// Forces a provider to re-evaluate its state immediately, and return the created value.
  ///
  /// This method is useful for features like "pull to refresh" or "retry on error",
  /// to restart a specific provider.
  Created refresh<Created>(ProviderBase<Created> provider) {
    final reader = _getStateReader(provider.providerToRefresh);

    if (reader._element != null) {
      final element = reader._element!;
      element.markMustRecomputeState();
    }

    return read(provider);
  }

  void _disposeProvider(ProviderBase<Object?> provider) {
    final element = readProviderElement(provider);
    element.dispose();

    final reader = _stateReaders[element._origin]!;

    if (reader.isOverride) {
      reader._element = null;
    } else {
      void removeStateReaderFrom(ProviderContainer container) {
        container._stateReaders.remove(element._origin);

        for (var i = 0; i < container._children.length; i++) {
          removeStateReaderFrom(container._children[i]);
        }
      }

      removeStateReaderFrom(this);
    }
  }

  /// Updates the list of provider overrides.
  ///
  /// If you are using flutter, this is done implicitly for you by `ProviderScope`.
  ///
  /// Updating a `overrideWithValue` with a different value
  /// will cause the listeners to rebuild.
  ///
  /// It is not possible, to remove or add new overrides, only update existing ones.
  void updateOverrides(List<Override> overrides) {
    if (_disposed) {
      throw StateError(
        'Called updateOverrides on a ProviderContainer that was already disposed',
      );
    }

    List<Override>? unusedOverrides;
    assert(() {
      unusedOverrides = [...overrides];
      return true;
    }(), '');

    for (final override in overrides) {
      if (override is ProviderOverride) {
        assert(() {
          unusedOverrides!.remove(override);
          return true;
        }(), '');

        void setupOverride({
          required ProviderBase override,
          required ProviderBase origin,
        }) {
          assert(
            _overrideForProvider[origin].runtimeType == override.runtimeType,
            'Replaced the override of type ${_overrideForProvider[origin].runtimeType} '
            'with an override of type ${override.runtimeType}, which is different.\n'
            'Changing the kind of override or reordering overrides is not supported.',
          );

          // _stateReaders[origin] cannot be null for overridden providers.
          final reader = _stateReaders[origin]!;

          reader.override = _overrideForProvider[origin] = override;

          final element = reader._element;
          if (element == null) return;

          _runUnaryGuarded(element.update, override);
        }

        override.setupOverride(setupOverride);
      } else if (override is FamilyOverride) {
        assert(() {
          unusedOverrides!.remove(override);
          return true;
        }(), '');
        // TODO assert family override did not change

        _overrideForFamily[override.overridenFamily]!.override = override;
      }
    }

    assert(
      unusedOverrides!.isEmpty,
      'Updated the list of overrides with providers that were not overriden before',
    );
  }

  /// Reads the state of a provider, potentially creating it in the process.
  ///
  /// It may throw if the provider requested threw when it was built.
  ///
  /// Do not use this in production code. This is exposed only for testing
  /// and devtools, to be able to test if a provider has listeners or similar.
  ProviderElementBase<State> readProviderElement<State>(
    ProviderBase<State> provider,
  ) {
    if (_disposed) {
      throw StateError(
        'Tried to read a provider from a ProviderContainer that was already disposed',
      );
    }

    final reader = _getStateReader(provider);

    return reader.getElement() as ProviderElementBase<State>;
  }

  _StateReader _getStateReader(ProviderBase provider) {
    return _stateReaders.putIfAbsent(provider, () {
      if (provider.from != null) {
        final familyOverrideRef = _overrideForFamily[provider.from];

        if (familyOverrideRef != null) {
          if (familyOverrideRef.container._stateReaders.containsKey(provider)) {
            return familyOverrideRef.container._stateReaders[provider]!;
          }

          void setupOverride({
            required ProviderBase origin,
            required ProviderBase override,
          }) {
            assert(
              !familyOverrideRef.container._stateReaders.containsKey(origin),
              'A family override tried to override a provider that was already overriden',
            );

            familyOverrideRef.container._stateReaders[origin] = _StateReader(
              origin: origin,
              override: override,
              container: familyOverrideRef.container,
              isOverride: true,
            );
          }

          familyOverrideRef.override.setupOverride(
            provider.argument,
            setupOverride,
          );

          assert(
            familyOverrideRef.container._stateReaders.containsKey(provider),
            'Overrode a family, but the family override did not override anything',
          );

          return familyOverrideRef.container._stateReaders[provider]!;
        }
      }

      if (_root?._stateReaders.containsKey(provider) ?? false) {
        return _root!._stateReaders[provider]!;
      }

      final reader = _StateReader(
        origin: provider,
        // If a provider did not have an associated StateReader then it is
        // guaranteed to not be overriden
        override: provider,
        container: _root ?? this,
        isOverride: false,
      );

      if (_root != null) _root!._stateReaders[provider] = reader;

      return reader;
    });
  }

  /// Release all the resources associated with this [ProviderContainer].
  ///
  /// This will destroy the state of all providers associated to this
  /// [ProviderContainer] and call [ProviderRefBase.onDispose] listeners.
  void dispose() {
    if (_disposed) {
      return;
    }
    if (_children.isNotEmpty) {
      throw StateError(
        'Tried to dispose a ProviderContainer that still has children containers.',
      );
    }

    assert(() {
      RiverpodBinding.debugInstance.containers =
          Map.from(RiverpodBinding.debugInstance.containers)..remove(_debugId);
      return true;
    }(), '');

    _parent?._children.remove(this);

    _disposed = true;

    for (final element in getAllProviderElementsInOrder().toList().reversed) {
      element.dispose();
    }
    _stateReaders.clear();
  }

  /// Traverse the [ProviderElementBase]s associated with this [ProviderContainer].
  Iterable<ProviderElementBase> getAllProviderElements() sync* {
    for (final reader in _stateReaders.values) {
      if (reader._element != null && reader.container == this) {
        yield reader._element!;
      }
    }
  }

  /// Visit all nodes of the graph at most once, from roots to leaves.
  ///
  /// This is fairly expensive and should be avoided as much as possible.
  /// If you do not need for providers to be sorted, consider using [getAllProviderElements]
  /// instead, which returns an unsorted list and is significantly faster.
  Iterable<ProviderElementBase> getAllProviderElementsInOrder() sync* {
    final visitedNodes = HashSet<ProviderElementBase>();
    final queue = DoubleLinkedQueue<ProviderElementBase>();

    // get roots of the provider graph
    for (final reader in _stateReaders.values) {
      if (reader.container != this) continue;
      final element = reader._element;
      if (element == null) continue;

      var hasAncestors = false;
      element.visitAncestors((element) {
        hasAncestors = true;
      });

      if (!hasAncestors) {
        queue.add(element);
      }
    }

    while (queue.isNotEmpty) {
      final element = queue.removeFirst();

      if (!visitedNodes.add(element)) {
        // Already visited
        continue;
      }

      yield element;

      // Queue the children of this element, but only if all of its ancestors
      // were already visited before.
      // If a child does not have all of its ancestors visited, when those
      // ancestors will be visited, they will retry visiting this child.
      element.visitChildren((dependent) {
        if (dependent.container == this) {
          // All the parents of a node must have been visited before a node is visited
          var areAllAncestorsAlreadyVisited = true;
          dependent.visitAncestors((e) {
            if (e._container == this && !visitedNodes.contains(e)) {
              areAllAncestorsAlreadyVisited = false;
            }
          });

          if (areAllAncestorsAlreadyVisited) queue.add(dependent);
        }
      });
    }
  }
}

/// An object that listens to the changes of a [ProviderContainer].
///
/// This can be used for logging or making devtools.
abstract class ProviderObserver {
  /// An object that listens to the changes of a [ProviderContainer].
  ///
  /// This can be used for logging or making devtools.
  const ProviderObserver();

  /// A provider was initialized, and the value exposed is [value].
  void didAddProvider(
    ProviderBase provider,
    Object? value,
    ProviderContainer container,
  ) {}

  /// Called my providers when they emit a notification.
  void didUpdateProvider(
    ProviderBase provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {}

  /// A provider was disposed
  void didDisposeProvider(
    ProviderBase provider,
    ProviderContainer containers,
  ) {}
}

/// An implementation detail for the override mechanism of providers
typedef SetupOverride = void Function({
  required ProviderBase origin,
  required ProviderBase override,
});

/// An object used by [ProviderContainer] to override the behavior of a provider
/// for a part of the application.
///
/// Do not implement/extend this class.
///
/// See also:
///
/// - [ProviderContainer], which uses this object.
/// - `overrideWithProvider`/`overrideWithValue`, which creates a [ProviderOverride].
class ProviderOverride implements Override {
  /// Override a provider
  ProviderOverride(this._setupOverride);

  final void Function(SetupOverride setup) _setupOverride;

  /// Defines how a provider should be overriden.
  void setupOverride(
    void Function({
      required ProviderBase origin,
      required ProviderBase override,
    })
        setup,
  ) {
    _setupOverride(setup);
  }
}

/// An object used by [ProviderContainer]/`ProviderScope` to override the behavior
/// of a provider/family for part of the application.
///
/// Do not extend or implement.
abstract class Override {}

/// An error thrown when a call to [ProviderRefBase.read]/[ProviderRefBase.watch]
/// leads to a provider depending on itself.
///
/// Circular dependencies are both not supported for performance reasons
/// and maintainability reasons.
/// Consider reading about unidirectional data-flow to learn about the
/// benefits of avoiding circular dependencies.
class CircularDependencyError extends Error {
  CircularDependencyError._();
}
