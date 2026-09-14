enum ServiceFailureKind {
  network,
  unauthorized,
  unavailable,
  invalidData,
  configuration,
  storage,
}

class ServiceException implements Exception {
  const ServiceException(this.kind);

  final ServiceFailureKind kind;

  @override
  String toString() => 'ServiceException(${kind.name})';
}
