import 'package:flutter_webrtc/webrtc.dart';

import 'baseconnection.dart';
import 'enums.dart';
import 'logger.dart';
import 'negotiator.dart';
import 'peer.dart';
import 'servermessage.dart';
import 'util.dart';

/**
 * Wraps the streaming interface between two Peers.
 */
class MediaConnection extends BaseConnection {
  static const ID_PREFIX = "mc_";

  Negotiator _negotiator;
  MediaStream localStream;
  MediaStream remoteStream;

  String get type {
    return ConnectionType.Media;
  }

  MediaConnection(String peerId, Peer provider, PeerConnectOption options)
      : super(peerId, provider, options) {
    this.localStream = this.options.stream;
    this.connectionId = this.options.connectionId ??
        MediaConnection.ID_PREFIX + util.randomToken();

    this._negotiator = new Negotiator(this);

    if (this.localStream != null) {
//  this._negotiator.startConnection({
//  _stream: this._localStream,
//  originator: true
//  });
    }
  }

  addStream(MediaStream remoteStream) {
    logger.log("Receiving stream" + remoteStream.toString());

    this.remoteStream = remoteStream;
    super.emit(ConnectionEventType.Stream,
        remoteStream); // Should we call this `open`?
  }

  handleMessage(ServerMessage message) {
    final type = message.type;
    final payload = message.payload;

    if (type == ServerMessageType.Answer) {
      // Forward to negotiator
      this._negotiator.handleSDP(type, payload.sdp);
      this.open = true;
    } else if (type == ServerMessageType.Candidate) {
      this._negotiator.handleCandidate(payload.candidate);
    } else {
      logger.warn('Unrecognized message type:${type} from peer:${this.peer}');
    }
  }

  answer(MediaStream stream, AnswerOption options) {
    if (this.localStream != null) {
      logger.warn(
          "Local stream already exists on this MediaConnection. Are you answering a call twice?");
      return;
    }

    this.localStream = stream;

    if (options != null && options.sdpTransform != null) {
      this.options.sdpTransform = options.sdpTransform;
    }

//this._negotiator.startConnection({ ...this.options._payload, _stream: stream });
// Retrieve lost messages stored because PeerConnection not set up.
    final messages = this.provider.getMessages(this.connectionId);

    for (final message in messages) {
      this.handleMessage(message);
    }

    this.open = true;
  }

  /**
   * Exposed functionality for users.
   */

  /** Allows user to close connection. */
  close() {
    if (this._negotiator != null) {
      this._negotiator.cleanup();
      this._negotiator = null;
    }

    this.localStream.dispose();
    this.remoteStream.dispose();
    this.localStream = null;
    this.remoteStream = null;

    if (this.provider != null) {
      this.provider.removeConnection(this);
    }

    if (this.options != null && this.options.stream != null) {
      this.options.stream.dispose();
      this.options.stream = null;
    }

    if (!this.open) {
      return;
    }

    this.open = false;

    super.emit(ConnectionEventType.Close);
  }
}
