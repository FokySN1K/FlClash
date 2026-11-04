// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../proxy_definition.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The mapping the running config holds for a node: the server, the port and
/// the secret that `/proxies` leaves out. A group, or a Core that cannot read
/// its config, answers null.

@ProviderFor(proxyDefinition)
final proxyDefinitionProvider = ProxyDefinitionFamily._();

/// The mapping the running config holds for a node: the server, the port and
/// the secret that `/proxies` leaves out. A group, or a Core that cannot read
/// its config, answers null.

final class ProxyDefinitionProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, dynamic>?>,
          Map<String, dynamic>?,
          FutureOr<Map<String, dynamic>?>
        >
    with
        $FutureModifier<Map<String, dynamic>?>,
        $FutureProvider<Map<String, dynamic>?> {
  /// The mapping the running config holds for a node: the server, the port and
  /// the secret that `/proxies` leaves out. A group, or a Core that cannot read
  /// its config, answers null.
  ProxyDefinitionProvider._({
    required ProxyDefinitionFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'proxyDefinitionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$proxyDefinitionHash();

  @override
  String toString() {
    return r'proxyDefinitionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Map<String, dynamic>?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, dynamic>?> create(Ref ref) {
    final argument = this.argument as String;
    return proxyDefinition(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProxyDefinitionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$proxyDefinitionHash() => r'680c57804016de0ef73dd91f9170239f8de38b81';

/// The mapping the running config holds for a node: the server, the port and
/// the secret that `/proxies` leaves out. A group, or a Core that cannot read
/// its config, answers null.

final class ProxyDefinitionFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Map<String, dynamic>?>, String> {
  ProxyDefinitionFamily._()
    : super(
        retry: null,
        name: r'proxyDefinitionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The mapping the running config holds for a node: the server, the port and
  /// the secret that `/proxies` leaves out. A group, or a Core that cannot read
  /// its config, answers null.

  ProxyDefinitionProvider call(String name) =>
      ProxyDefinitionProvider._(argument: name, from: this);

  @override
  String toString() => r'proxyDefinitionProvider';
}
