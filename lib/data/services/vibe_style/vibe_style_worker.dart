import 'dart:async';
import 'dart:isolate';
import '../../models/vibe/vibe_family.dart';
import 'vibe_style_corpus.dart';
import 'vibe_style_features.dart';
import 'vibe_style_matcher.dart';

class VibeStyleCancelled implements Exception {}

/// One killable worker at a time. Timeouts terminate the isolate, including decode.
class VibeStyleWorker {
  _Job? _active;

  Future<T> run<T>(String operation, Object argument,
      {Duration timeout = const Duration(seconds: 30)}) async {
    if (_active != null) throw StateError('worker already busy');
    final job = _Job();
    _active = job;
    job.subscription = job.port.listen((dynamic message) {
      if (job.result.isCompleted) return;
      if (message is List && message.length == 2 && message[0] is bool) {
        if (message[0] == true) {
          job.result.complete(message[1]);
        } else {
          job.result.completeError(StateError(message[1].toString()));
        }
      } else {
        job.result.completeError(StateError('Vibe analysis worker exited'));
      }
    });
    job.timer = Timer(timeout, () {
      job.isolate?.kill(priority: Isolate.immediate);
      if (!job.result.isCompleted) job.result.completeError(TimeoutException(operation));
    });
    // Start listening to the completion before spawn can finish or cancellation occurs.
    final result = job.result.future;
    unawaited(Isolate.spawn<List<Object?>>(_entry, [job.port.sendPort, operation, argument],
      onExit: job.port.sendPort, onError: job.port.sendPort).then((isolate) {
        job.isolate = isolate;
        if (job.result.isCompleted) isolate.kill(priority: Isolate.immediate);
      }, onError: (Object error, StackTrace stack) {
        if (!job.result.isCompleted) job.result.completeError(error, stack);
      }));
    try {
      return await result as T;
    } finally {
      job.isolate?.kill(priority: Isolate.immediate);
      job.timer?.cancel();
      await job.subscription?.cancel();
      job.port.close();
      if (identical(_active, job)) _active = null;
    }
  }

  void cancel() {
    final job = _active;
    job?.isolate?.kill(priority: Isolate.immediate);
    if (job != null && !job.result.isCompleted) {
      job.result.completeError(VibeStyleCancelled());
    }
  }

  static Future<void> _entry(List<Object?> request) async {
    final port = request[0]! as SendPort;
    try {
      final data = request[2];
      final Object? result;
      switch (request[1]) {
        case 'parse':
          result = VibeStyleCorpus.parse(data! as List<Map<String,Object?>>);
        case 'select':
          result = VibeStyleCorpus.select(data! as List<VibeStyleSample>);
        case 'features':
          result = await VibeStyleFeatures.read(data! as VibeStyleSample);
        case 'rank':
          final args = data! as List;
          result = VibeStyleMatcher.rank(args[0] as List<VibeStyleSample>,
            args[1] as Map<String,List<List<double>>>);
        default:
          throw ArgumentError('Unknown Vibe analysis operation');
      }
      port.send([true, result]);
    } catch (error) {
      port.send([false, error.toString()]);
    }
  }
}

class _Job {
  final port = ReceivePort();
  final result = Completer<Object?>();
  StreamSubscription<dynamic>? subscription;
  Isolate? isolate;
  Timer? timer;
}
