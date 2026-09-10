import 'package:analyzer/dart/element/type.dart';

const _treePackagePrefix = 'package:genesis_tree/';

/// Whether [type] is `TreeContext`, or implements it, from `genesis_tree`.
///
/// Extension types are matched through their representation type. A class
/// with the same name from any other library is deliberately not matched.
bool isTreeContextType(DartType? type) =>
    _isGenesisInterface(type, const {'TreeContext'});

/// Whether [type] is a `Branch` or `TreeContext` implementation managed by
/// `genesis_tree`.
///
/// Storage owned by one of these types is framework storage, rather than an
/// unmanaged object retaining a tree capability.
bool isTreeManagedType(DartType? type) =>
    _isGenesisInterface(type, const {'Branch', 'TreeContext'});

bool _isGenesisInterface(DartType? type, Set<String> names) {
  final erasedType = type?.extensionTypeErasure;
  if (erasedType is! InterfaceType) return false;

  return <InterfaceType>[erasedType, ...erasedType.allSupertypes].any((type) {
    final element = type.element;
    return names.contains(element.name) &&
        element.library.uri.toString().startsWith(_treePackagePrefix);
  });
}
