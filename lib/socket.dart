import 'dart:async';
import 'dart:convert';

import 'package:eventify/eventify.dart';
import 'package:web_socket_channel/io.dart';

import 'enums.dart';
import 'logger.dart';
import 'peer.dart';

/**
 * An abstraction on top of WebSockets to provide fastest
 * possible connection for peers.
 */
class Socket extends EventEmitter {
  var _disconnected = true;
  String _id;
  var _messagesQueue = [];
  IOWebSocketChannel _socket;
  StreamSubscription _socketListener;
  dynamic _wsPingTimer;
  String _baseUrl;
  PeerOptions options;

  Socket(this.options) {
    options.pingInterval = options.pingInterval ?? 5000;

    final wsProtocol = options.secure ? "wss://" : "ws://";

    this._baseUrl = wsProtocol +
        options.host +
        ":" +
        options.port.toString() +
        options.path +
        "peerjs?key=" +
        options.key;
  }

  start(String id, String token) {
    this._id = id;

    final wsUrl = '$_baseUrl&id=$id&token=$token';

    if (this._socket != null || !this._disconnected) {
      return;
    }

    this._socket = IOWebSocketChannel.connect(wsUrl);
    this._disconnected = false;

    _socketListener = this._socket.stream.listen((event) {
      var data;

      try {
        data = jsonEncode(event);
        logger.log("Server message received:" + data.toString());
      } catch (e) {
        logger.log("Invalid server message" + event.toString());
        return;
      }

      this.emit(SocketEventType.Message, event);
    }, onDone: () {
      if (this._disconnected) {
        return;
      }

      logger.log("Socket closed.");
      this.emit(SocketEventType.Disconnected);

      this._cleanup();
      this._disconnected = true;
    });

    // Take care of the queue of connections if necessary and make sure Peer knows
    // socket is open.
    this._sendQueuedMessages();

    logger.log("Socket open");

    this._scheduleHeartbeat();
  }

  _scheduleHeartbeat() {
    this._wsPingTimer =
        Future.delayed(Duration(milliseconds: options.pingInterval), () {
      this._sendHeartbeat();
    });
  }

  _sendHeartbeat() {
    if (!this._wsOpen()) {
      logger.log('Cannot send heartbeat, because socket closed');
      return;
    }

    final message = {'type': ServerMessageType.Heartbeat};

    this._socket.sink.add(message);

    this._scheduleHeartbeat();
  }

  /** Is the websocket currently open? */
  bool _wsOpen() {
    return this._socket != null && this._socket.protocol != null;
  }

  /** Send queued messages. */
  _sendQueuedMessages() {
//Create copy of queue and clear it,
//because send method push the message back to queue if smth will go wrong
    final copiedQueue = [];
    copiedQueue.addAll(this._messagesQueue);
    this._messagesQueue = [];

    for (final message in copiedQueue) {
      this.send(message);
    }
  }

  /** Exposed send for DC & Peer. */
  send(dynamic data) {
    if (this._disconnected) {
      return;
    }

// If we didn't get an ID yet, we can't yet send anything so we should queue
// up these messages.
    if (this._id == null) {
      this._messagesQueue.add(data);
      return;
    }

    if (!data['type']) {
      this.emit(SocketEventType.Error, "Invalid message");
      return;
    }

    if (!this._wsOpen()) {
      return;
    }

    this._socket.sink.add(data);
  }

  close() {
    if (this._disconnected) {
      return;
    }

    this._cleanup();

    this._disconnected = true;
  }

  _cleanup() {
    if (this._socket != null) {
      _socketListener.cancel();
      super.clear();
    }
  }
}
