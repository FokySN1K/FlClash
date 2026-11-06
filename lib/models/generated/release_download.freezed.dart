// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of '../release_download.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ReleaseDownloadState {

 ReleaseDownloadPhase? get phase; int get received; int get total; Object? get error;
/// Create a copy of ReleaseDownloadState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReleaseDownloadStateCopyWith<ReleaseDownloadState> get copyWith => _$ReleaseDownloadStateCopyWithImpl<ReleaseDownloadState>(this as ReleaseDownloadState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ReleaseDownloadState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReleaseDownloadState&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.received, _this.received) || other.received == _this.received)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.error, _this.error));
}


@override
int get hashCode {
  final _this = this as ReleaseDownloadState;
  return Object.hash(runtimeType,_this.phase,_this.received,_this.total,const DeepCollectionEquality().hash(_this.error));
}

@override
String toString() {
  final _this = this as ReleaseDownloadState;
  return 'ReleaseDownloadState(phase: ${_this.phase}, received: ${_this.received}, total: ${_this.total}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $ReleaseDownloadStateCopyWith<$Res>  {
  factory $ReleaseDownloadStateCopyWith(ReleaseDownloadState value, $Res Function(ReleaseDownloadState) _then) = _$ReleaseDownloadStateCopyWithImpl;
@useResult
$Res call({
 ReleaseDownloadPhase? phase, int received, int total, Object? error
});




}
/// @nodoc
class _$ReleaseDownloadStateCopyWithImpl<$Res>
    implements $ReleaseDownloadStateCopyWith<$Res> {
  _$ReleaseDownloadStateCopyWithImpl(this._self, this._then);

  final ReleaseDownloadState _self;
  final $Res Function(ReleaseDownloadState) _then;

/// Create a copy of ReleaseDownloadState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = freezed,Object? received = null,Object? total = null,Object? error = freezed,}) {
  return _then(ReleaseDownloadState(
phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as ReleaseDownloadPhase?,received: null == received ? _self.received : received // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error ,
  ));
}

}


/// Adds pattern-matching-related methods to [ReleaseDownloadState].
extension ReleaseDownloadStatePatterns on ReleaseDownloadState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReleaseDownloadState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReleaseDownloadState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReleaseDownloadState value)  $default,){
final _that = this;
switch (_that) {
case _ReleaseDownloadState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReleaseDownloadState value)?  $default,){
final _that = this;
switch (_that) {
case _ReleaseDownloadState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReleaseDownloadPhase? phase,  int received,  int total,  Object? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReleaseDownloadState() when $default != null:
return $default(_that.phase,_that.received,_that.total,_that.error);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReleaseDownloadPhase? phase,  int received,  int total,  Object? error)  $default,) {final _that = this;
switch (_that) {
case _ReleaseDownloadState():
return $default(_that.phase,_that.received,_that.total,_that.error);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReleaseDownloadPhase? phase,  int received,  int total,  Object? error)?  $default,) {final _that = this;
switch (_that) {
case _ReleaseDownloadState() when $default != null:
return $default(_that.phase,_that.received,_that.total,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _ReleaseDownloadState implements ReleaseDownloadState {
  const _ReleaseDownloadState({this.phase, this.received = 0, this.total = 0, this.error});
  

@override final  ReleaseDownloadPhase? phase;
@override@JsonKey() final  int received;
@override@JsonKey() final  int total;
@override final  Object? error;

/// Create a copy of ReleaseDownloadState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReleaseDownloadStateCopyWith<_ReleaseDownloadState> get copyWith => __$ReleaseDownloadStateCopyWithImpl<_ReleaseDownloadState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReleaseDownloadState&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.received, received) || other.received == received)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.error, error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,received,total,const DeepCollectionEquality().hash(error));
}

@override
String toString() {
    return 'ReleaseDownloadState(phase: $phase, received: $received, total: $total, error: $error)';
}


}

/// @nodoc
abstract mixin class _$ReleaseDownloadStateCopyWith<$Res> implements $ReleaseDownloadStateCopyWith<$Res> {
  factory _$ReleaseDownloadStateCopyWith(_ReleaseDownloadState value, $Res Function(_ReleaseDownloadState) _then) = __$ReleaseDownloadStateCopyWithImpl;
@override @useResult
$Res call({
 ReleaseDownloadPhase? phase, int received, int total, Object? error
});




}
/// @nodoc
class __$ReleaseDownloadStateCopyWithImpl<$Res>
    implements _$ReleaseDownloadStateCopyWith<$Res> {
  __$ReleaseDownloadStateCopyWithImpl(this._self, this._then);

  final _ReleaseDownloadState _self;
  final $Res Function(_ReleaseDownloadState) _then;

/// Create a copy of ReleaseDownloadState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = freezed,Object? received = null,Object? total = null,Object? error = freezed,}) {
  return _then(_ReleaseDownloadState(
phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as ReleaseDownloadPhase?,received: null == received ? _self.received : received // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error ,
  ));
}


}

// dart format on
