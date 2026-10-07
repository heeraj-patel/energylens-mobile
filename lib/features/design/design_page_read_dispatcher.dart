import 'design_context_coordinator.dart';

/// Holds page reads in native memory until an approved presentation uses them.
/// Navigation and account lifecycle changes invalidate every pending result.
class DesignPageReadDispatcher {
  DesignPageReadDispatcher(this._coordinator);

  DesignContextCoordinator? _coordinator;
  int _generation = 0;
  bool _disposed = false;
  String? _page;
  VerifiedDesignContext? _readContext;
  int? _contextGeneration;
  DesignContextRead? _latestRead;
  Object? _latestError;

  DesignContextRead? get latestRead =>
      !_disposed &&
          _contextGeneration == _coordinator?.generation &&
          identical(_readContext, _coordinator?.context)
      ? _latestRead
      : null;
  Object? get latestError =>
      !_disposed &&
          _contextGeneration == _coordinator?.generation &&
          identical(_readContext, _coordinator?.context)
      ? _latestError
      : null;

  void useCoordinator(DesignContextCoordinator? coordinator) {
    if (identical(_coordinator, coordinator)) return;
    clear();
    _coordinator = coordinator;
  }

  void clear() {
    _generation++;
    _page = null;
    _readContext = null;
    _contextGeneration = null;
    _latestRead = null;
    _latestError = null;
  }

  void dispose() {
    clear();
    _disposed = true;
    _coordinator = null;
  }

  Future<void> load(String page) async {
    if (_disposed) return;
    clear();
    _page = page;
    final coordinator = _coordinator;
    final context = coordinator?.context;
    if (coordinator == null ||
        context == null ||
        !coordinator.supportsPageRead(page)) {
      return;
    }
    _readContext = context;
    _contextGeneration = coordinator.generation;
    final generation = _generation;
    bool stale() =>
        _disposed ||
        generation != _generation ||
        _page != page ||
        !identical(_coordinator, coordinator) ||
        _contextGeneration != coordinator.generation ||
        !identical(coordinator.context, context);
    try {
      final result = await coordinator.read(page);
      if (!stale()) _latestRead = result;
    } catch (error) {
      if (!stale()) _latestError = error;
    }
  }
}
