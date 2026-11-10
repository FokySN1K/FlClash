// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../route_targets.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The outbounds the applied rules send traffic to, in the order the rules
/// first reach them. Asked again when the Core moves its route counters: a
/// profile switch or a mode change rewrites the rules wholesale, and a Core
/// that cannot answer leaves the map empty.

@ProviderFor(routeTargets)
final routeTargetsProvider = RouteTargetsProvider._();

/// The outbounds the applied rules send traffic to, in the order the rules
/// first reach them. Asked again when the Core moves its route counters: a
/// profile switch or a mode change rewrites the rules wholesale, and a Core
/// that cannot answer leaves the map empty.

final class RouteTargetsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RouteTarget>>,
          List<RouteTarget>,
          FutureOr<List<RouteTarget>>
        >
    with
        $FutureModifier<List<RouteTarget>>,
        $FutureProvider<List<RouteTarget>> {
  /// The outbounds the applied rules send traffic to, in the order the rules
  /// first reach them. Asked again when the Core moves its route counters: a
  /// profile switch or a mode change rewrites the rules wholesale, and a Core
  /// that cannot answer leaves the map empty.
  RouteTargetsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routeTargetsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routeTargetsHash();

  @$internal
  @override
  $FutureProviderElement<List<RouteTarget>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<RouteTarget>> create(Ref ref) {
    return routeTargets(ref);
  }
}

String _$routeTargetsHash() => r'b02cea625f005c76ef02c18c7043ecc169889a0b';
