// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../proxy_details.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// What the sheet shows about one node beyond its card. The history is made of
/// the checks [delayProvider] reports, so watching it reads the details again
/// once a result lands; a name the Core no longer holds reads as null.

@ProviderFor(proxyDetails)
final proxyDetailsProvider = ProxyDetailsFamily._();

/// What the sheet shows about one node beyond its card. The history is made of
/// the checks [delayProvider] reports, so watching it reads the details again
/// once a result lands; a name the Core no longer holds reads as null.

final class ProxyDetailsProvider
    extends
        $FunctionalProvider<
          AsyncValue<ProxyDetails?>,
          ProxyDetails?,
          FutureOr<ProxyDetails?>
        >
    with $FutureModifier<ProxyDetails?>, $FutureProvider<ProxyDetails?> {
  /// What the sheet shows about one node beyond its card. The history is made of
  /// the checks [delayProvider] reports, so watching it reads the details again
  /// once a result lands; a name the Core no longer holds reads as null.
  ProxyDetailsProvider._({
    required ProxyDetailsFamily super.from,
    required ({String proxyName, String? testUrl}) super.argument,
  }) : super(
         retry: null,
         name: r'proxyDetailsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$proxyDetailsHash();

  @override
  String toString() {
    return r'proxyDetailsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<ProxyDetails?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ProxyDetails?> create(Ref ref) {
    final argument = this.argument as ({String proxyName, String? testUrl});
    return proxyDetails(
      ref,
      proxyName: argument.proxyName,
      testUrl: argument.testUrl,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProxyDetailsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$proxyDetailsHash() => r'9242c2d92e94f8dd358486bdc701bde99ca10df8';

/// What the sheet shows about one node beyond its card. The history is made of
/// the checks [delayProvider] reports, so watching it reads the details again
/// once a result lands; a name the Core no longer holds reads as null.

final class ProxyDetailsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<ProxyDetails?>,
          ({String proxyName, String? testUrl})
        > {
  ProxyDetailsFamily._()
    : super(
        retry: null,
        name: r'proxyDetailsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// What the sheet shows about one node beyond its card. The history is made of
  /// the checks [delayProvider] reports, so watching it reads the details again
  /// once a result lands; a name the Core no longer holds reads as null.

  ProxyDetailsProvider call({required String proxyName, String? testUrl}) =>
      ProxyDetailsProvider._(
        argument: (proxyName: proxyName, testUrl: testUrl),
        from: this,
      );

  @override
  String toString() => r'proxyDetailsProvider';
}
