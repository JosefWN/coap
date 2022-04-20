/*
 * Package : Coap
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 21/05/2018
 * Copyright :  S.Hamblett
 */

part of coap;

/// Crop rotation deduplicator
class CoapCropRotationDeduplicator implements CoapIDeduplicator {
  /// Construction
  CoapCropRotationDeduplicator(this._config)
      : _maps = List<Map<int?, CoapExchange>>.filled(3, <int?, CoapExchange>{});

  final List<Map<int?, CoapExchange>> _maps;
  int _first = 0;
  int _second = 1;
  late Timer _timer;
  final DefaultCoapConfig _config;

  @override
  void start() {
    _timer = Timer.periodic(
        Duration(milliseconds: _config.cropRotationPeriod), _rotation);
  }

  @override
  void stop() {
    _timer.cancel();
  }

  @override
  void clear() {
    stop();
    _maps.clear();
  }

  @override
  CoapExchange? findPrevious(int? key, CoapExchange exchange) {
    CoapExchange? prev;
    if (_maps[_first].containsKey(key)) {
      prev = _maps[_first][key];
    }
    _maps[_first][key] = exchange;
    if (prev != null || _first == _second) {
      return prev;
    }
    if (_maps[_second].containsKey(key)) {
      prev = _maps[_second][key];
    }
    _maps[_second][key] = exchange;
    return prev;
  }

  @override
  CoapExchange? find(int? key) {
    if (_maps[_first].containsKey(key) || _first == _second) {
      return _maps[_first][key];
    }
    if (_maps[_second].containsKey(key)) {
      return _maps[_second][key];
    }
    return null;
  }

  void _rotation(Timer timer) {
    final third = _first;
    _first = _second;
    _second = (_second + 1) % 3;
    _maps[third].clear();
  }
}
