/// A [Sink] that forwards each element to a callback.
///
/// What a chunked converter needs on its output side when the consumer is a
/// plain function rather than a stream.
final class CallbackSink<T> implements Sink<T> {
  const CallbackSink(this._onData);

  final void Function(T data) _onData;

  @override
  void add(T data) => _onData(data);

  @override
  void close() {}
}
