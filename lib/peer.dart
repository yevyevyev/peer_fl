import 'package:eventify/eventify.dart';
import 'package:flutter_webrtc/webrtc.dart';

import 'api.dart';
import 'baseconnection.dart';
import 'enums.dart';
import 'logger.dart';
import 'mediaconnection.dart';
import 'servermessage.dart';
import 'socket.dart';
import 'util.dart';

/**
 * A peer who can initiate connections with other peers.
 */

class PeerOptions {
  Function logFunction;
  String host;
  int port;
  int debug;
  String path;
  String key;
  String token;
  Map<String, dynamic> config;
  bool secure;
  int pingInterval;

  PeerOptions({
    this.logFunction,
    this.host = Util.CLOUD_HOST,
    this.port = Util.CLOUD_PORT,
    this.debug = 0,
    this.path = '/',
    this.key = Peer.DEFAULT_KEY,
    this.token,
    this.config = Util.defaultConfig,
    this.secure,
    this.pingInterval,
  }) {
    token = util.randomToken();
  }
}

class PeerConnectOption {
  String label;
  dynamic metadata;
  String serialization;
  bool reliable;
  MediaStream stream;
  String connectionId;
  Function sdpTransform;
  dynamic originator;
  Map<String, dynamic> payload;
  RTCSessionDescription sdp;
  Map<String, dynamic> constraints;

  PeerConnectOption(
      {this.label,
      this.metadata,
      this.serialization,
      this.reliable,
      this.stream,
      this.connectionId,
      this.sdpTransform,
      this.originator,
      this.payload,
      this.sdp,
      this.constraints});
}

mixin CallOption {
  dynamic metadata;
  Function sdpTransform;
}

mixin AnswerOption {
  Function sdpTransform;
}

class Peer extends EventEmitter {
  static const DEFAULT_KEY = "peerjs";

  PeerOptions options;
  API _api;
  Socket socket;

  String id;
  String _lastServerId;

  // States.
  var destroyed = false; // Connections have been killed
  var disconnected =
      false; // Connection to PeerServer killed but P2P connections still active
  var open = false; // Sockets and such are not yet open.
  Map<String, List<BaseConnection>> _connections =
      {}; // All connections for this peer.
  Map<String, List<ServerMessage>> _lostMessages =
      {}; // src => [list of messages]

  Peer(dynamic id, PeerOptions options) {
    String userId;

// Deal with overloading
    if (id != null && id is PeerOptions) {
      options = id;
    } else if (id != null) {
      userId = id.toString();
    }

// Configurize options
    this.options = options;

// Detect relative URL host.

// Set path correctly.
    if (this.options.path != null) {
      if (this.options.path[0] != "/") {
        this.options.path = "/" + this.options.path;
      }
      if (this.options.path[this.options.path.length - 1] != "/") {
        this.options.path += "/";
      }
    }

// Set whether we use SSL to same as current host
    if (this.options.secure == null && this.options.host != Util.CLOUD_HOST) {
      this.options.secure = true;
    } else if (this.options.host == Util.CLOUD_HOST) {
      this.options.secure = true;
    }
// Set a custom log function if present
    if (this.options.logFunction != null) {
      logger.setLogFunction(this.options.logFunction);
    }

    logger.logLevel = this.options.debug ?? 0;

    this._api = new API(options);
    this.socket = this._createServerConnection();

// Ensure alphanumeric id
    if (userId != null && !util.validateId(userId)) {
      this._delayedAbort(PeerErrorType.InvalidID, 'ID "${userId}" is invalid');
      return;
    }

    if (userId != null) {
      this._initialize(userId);
    } else {
      this._api.retrieveId().then(((id) => this._initialize(id))).catchError(
          ((error) => this._abort(PeerErrorType.ServerError, error)));
    }
  }

  Socket _createServerConnection() {
    final socket = new Socket(options);

    socket.on(SocketEventType.Message, this, ((evt, ctx) {
      //this._handleMessage(evt);
    }));

    socket.on(SocketEventType.Error, this, ((error, ctx) {
      this._abort(PeerErrorType.SocketError, error);
    }));

    socket.on(SocketEventType.Disconnected, this, ((_, __) {
      if (this.disconnected) {
        return;
      }

      this.emitError(PeerErrorType.Network, "Lost connection to server.");
      this.disconnect();
    }));

    socket.on(SocketEventType.Close, this, ((_, __) {
      if (this.disconnected) {
        return;
      }

      this._abort(
          PeerErrorType.SocketClosed, "Underlying socket is already closed.");
    }));

    return socket;
  }

  /** Initialize a connection with the server. */
  _initialize(String id) {
    this.id = id;
    this.socket.start(id, this.options.token);
  }

  /** Handles messages from the server. */
  _handleMessage(ServerMessage message) {
    final type = message.type;
    final payload = message.payload;
    final peerId = message.src;

    if (type == ServerMessageType.Open) {
      this._lastServerId = this.id;
      this.open = true;
      this.emit(PeerEventType.Open, this.id);
    } else if (type == ServerMessageType.Error) {
      this._abort(PeerErrorType.ServerError, payload.msg);
    } else if (type == ServerMessageType.IdTaken) {
      this._abort(PeerErrorType.UnavailableID, 'ID "${this.id}" is taken');
    } else if (type == ServerMessageType.InvalidKey) {
      this._abort(
          PeerErrorType.InvalidKey, 'API KEY "${this.options.key}" is invalid');
    } else if (type == ServerMessageType.Leave) {
      logger.log('Received leave message from ${peerId}');
      this._cleanupPeer(peerId);
      this._connections.removeWhere((k, v) => k == peerId);
    } else if (type == ServerMessageType.Expire) {
      this.emitError(
          PeerErrorType.PeerUnavailable, 'Could not connect to peer ${peerId}');
    } else if (type == ServerMessageType.Offer) {
// we should consider switching this to CALL/CONNECT, but this is the least breaking option.
      final connectionId = payload.connectionId;
      var connection = this.getConnection(peerId, connectionId);

      if (connection != null) {
        connection.close();
        logger
            .warn('Offer received for existing Connection ID:${connectionId}');
      }

// Create a new connection.
      if (payload.type == ConnectionType.Media) {
        connection = new MediaConnection(
          peerId,
          this,
          PeerConnectOption(
              connectionId: connectionId,
              payload: payload,
              metadata: payload.metadata),
        );
        this._addConnection(peerId, connection);
        this.emit(PeerEventType.Call, connection);
      }
//else if (payload.type === ConnectionType.Data) {
//connection = new DataConnection(peerId, this, {
//connectionId: connectionId,
//_payload: payload,
//metadata: payload.metadata,
//label: payload.label,
//serialization: payload.serialization,
//reliable: payload.reliable
//});
//this._addConnection(peerId, connection);
//this.emit(PeerEventType.Connection, connection);
//}
      else {
        logger.warn('Received malformed connection type:${payload.type}');
        return;
      }

// Find messages.
      final messages = this.getMessages(connectionId);
      for (final message in messages) {
        connection.handleMessage(message);
      }
    } else {
      if (!payload) {
        logger.warn(
            'You received a malformed message from ${peerId} of type ${type}');
        return;
      }

      final connectionId = payload.connectionId;
      final connection = this.getConnection(peerId, connectionId);

      if (connection != null && connection.peerConnection != null) {
// Pass it on.
        connection.handleMessage(message);
      } else if (connectionId) {
// Store for possible later use
        this._storeMessage(connectionId, message);
      } else {
        logger
            .warn("You received an unrecognized message:" + message.toString());
      }
    }
  }

  /** Stores messages without a set up connection, to be claimed later. */
  _storeMessage(String connectionId, ServerMessage message) {
    if (!this._lostMessages.containsKey(connectionId)) {
      this._lostMessages[connectionId] = [];
    }

    this._lostMessages[connectionId].add(message);
  }

  /** Retrieve messages from lost message store */
  List<ServerMessage> getMessages(String connectionId) {
    if (!this._lostMessages.containsKey(connectionId)) {
      return [];
    }

    final messages = this._lostMessages[connectionId];

    this._lostMessages.remove(connectionId);
    return messages;
  }

  /**
   * Returns a MediaConnection to the specified peer. See documentation for a
   * complete list of options.
   */
  MediaConnection call(
      String peer, MediaStream stream, PeerConnectOption options) {
    if (this.disconnected) {
      logger.warn("You cannot connect to a new Peer because you called " +
          ".disconnect() on this Peer and ended your connection with the " +
          "server. You can create a new Peer to reconnect.");
      this.emitError(PeerErrorType.Disconnected,
          "Cannot connect to new Peer after disconnecting from server.");
      return null;
    }

    if (stream == null) {
      logger.error(
          "To call a peer, you must provide a stream from your browser's `getUserMedia`.");
      return null;
    }

    options.stream = stream;

    final mediaConnection = new MediaConnection(peer, this, options);
    this._addConnection(peer, mediaConnection);
    return mediaConnection;
  }

  /** Add a data/media connection to this peer. */
  _addConnection(String peerId, BaseConnection connection) {
    logger.log(
        'add connection ${connection.type}:${connection.connectionId} to peerId:${peerId}');

    if (!this._connections.containsKey(peerId)) {
      this._connections[peerId] = [];
    }
    this._connections[peerId].add(connection);
  }

  removeConnection(BaseConnection connection) {
    if (!this._connections.containsKey(connection.peer)) {
      return;
    }

    final connections = this._connections[connection.peer];

    final index = connections
        .indexWhere((c) => c.connectionId == connection.connectionId);

    if (index != -1) {
      connections.removeAt(index);
    }

//remove from lost messages
    this._lostMessages.removeWhere(((k, v) => k == connection.connectionId));
  }

  /** Retrieve a data/media connection for this peer. */
  BaseConnection getConnection(String peerId, String connectionId) {
    if (!this._connections.containsKey(peerId)) {
      return null;
    }
    final connections = this._connections[peerId];

    for (final connection in connections) {
      if (connection.connectionId == connectionId) {
        return connection;
      }
    }

    return null;
  }

  _delayedAbort(String type, dynamic message) {
    Future.delayed(Duration(milliseconds: 0), () {
      this._abort(type, message);
    });
  }

  /**
   * Emits an error message and destroys the Peer.
   * The Peer is not destroyed if it's in a disconnected state, in which case
   * it retains its disconnected state and its existing connections.
   */
  _abort(String type, dynamic message) {
    logger.error("Aborting!");

    this.emitError(type, message);

    if (this._lastServerId != null) {
      this.destroy();
    } else {
      this.disconnect();
    }
  }

  /** Emits a typed error message. */
  emitError(String type, dynamic err) {
    logger.error("Error:" + err.toString());

    this.emit(PeerEventType.Error, err.toString());
  }

  /**
   * Destroys the Peer: closes all active connections as well as the connection
   *  to the server.
   * Warning: The peer can no longer create or accept connections after being
   *  destroyed.
   */
  destroy() {
    if (this.destroyed) {
      return;
    }

    logger.log('Destroy peer with ID:${this.id}');

    this.disconnect();
    this._cleanup();

    this.destroyed = true;

    this.emit(PeerEventType.Close);
  }

  /** Disconnects every connection on this peer. */
  _cleanup() {
    for (final peerId in this._connections.keys) {
      this._cleanupPeer(peerId);
    }

    this.socket.clear();
  }

  /** Closes all connections to this peer. */
  _cleanupPeer(String peerId) {
    if (!this._connections.containsKey(peerId)) {
      return;
    }
    final connections = this._connections[peerId];

    for (final connection in connections) {
      connection.close();
    }
  }

  /**
   * Disconnects the Peer's connection to the PeerServer. Does not close any
   *  active connections.
   * Warning: The peer can no longer create or accept connections after being
   *  disconnected. It also cannot reconnect to the server.
   */
  disconnect() {
    if (this.disconnected) {
      return;
    }

    final currentId = this.id;

    logger.log('Disconnect peer with ID:${currentId}');

    this.disconnected = true;
    this.open = false;

    this.socket.close();

    this._lastServerId = currentId;
    this.id = null;

    this.emit(PeerEventType.Disconnected, currentId);
  }

  /** Attempts to reconnect with the same ID. */
  reconnect() {
    if (this.disconnected && !this.destroyed) {
      logger.log(
          'Attempting reconnection to server with ID ${this._lastServerId}');
      this.disconnected = false;
      this._initialize(this._lastServerId);
    } else if (this.destroyed) {
      throw new Exception(
          "This peer cannot reconnect to the server. It has already been destroyed.");
    } else if (!this.disconnected && !this.open) {
// Do nothing. We're still connecting the first time.
      logger.error(
          "In a hurry? We're still trying to make the initial connection!");
    } else {
      throw new Exception(
          'Peer ${this.id} cannot reconnect because it is not disconnected from the server!');
    }
  }
}
