class FrameMetrics {
  FrameMetrics({this.window = const Duration(seconds: 2)});

  final Duration window;
  final List<Duration> _completed = [];
  int framesReceived = 0;
  int framesDropped = 0;
  Duration lastProcessing = Duration.zero;
  double _avgMs = 0;

  double get averageProcessingMs => _avgMs;

  void onFrameReceived() => framesReceived++;

  void onFrameDropped() => framesDropped++;

  void onFrameAnalyzed(Duration now, Duration processing) {
    lastProcessing = processing;
    final ms = processing.inMicroseconds / 1000;
    _avgMs = _avgMs == 0 ? ms : _avgMs * 0.85 + ms * 0.15;
    _completed.add(now);
    while (_completed.isNotEmpty && now - _completed.first > window) {
      _completed.removeAt(0);
    }
  }

  double get analysisFps {
    if (_completed.length < 2) return 0;
    final span = _completed.last - _completed.first;
    if (span == Duration.zero) return 0;
    return (_completed.length - 1) * 1e6 / span.inMicroseconds;
  }

  void reset() {
    _completed.clear();
    framesReceived = 0;
    framesDropped = 0;
    lastProcessing = Duration.zero;
    _avgMs = 0;
  }
}
