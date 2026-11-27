import 'package:synchronized/synchronized.dart';

final _lock = Lock();

Future<T> withContactImportLock<T>(String key, Future<T> Function() run) =>
    _lock.synchronized(run);
