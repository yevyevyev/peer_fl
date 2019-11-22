import 'package:flutter_webrtc/webrtc.dart';

import 'baseconnection.dart';
import 'enums.dart';
import 'logger.dart';
import 'mediaconnection.dart';
import 'peer.dart';

/**
 * Manages all negotiations between Peers.
 */
class Negotiator {
  final BaseConnection connection;

  Negotiator(this.connection);

  /** Returns a PeerConnection object set up correctly (for data, media). */
  startConnection(PeerConnectOption options) async {
    final peerConnection = this._startPeerConnection();

    // Set the connection's PC.
    this.connection.peerConnection = peerConnection;

    if (this.connection.type == ConnectionType.Media &&
        options.stream != null) {
      this._addTracksToConnection(options.stream, peerConnection);
    }

    // What do we need to do now?
    if (options.originator != null) {
      this._makeOffer();
    } else {
      this.handleSDP("OFFER", options.sdp);
    }
  }

  /** Start a PC. */
  RTCPeerConnection _startPeerConnection() {
    logger.log("Creating RTCPeerConnection.");

    final peerConnection = new RTCPeerConnection(
        this.connection.connectionId, this.connection.provider.options.config);

    this._setupListeners(peerConnection);

    return peerConnection;
  }

  /** Set up various WebRTC listeners. */
  _setupListeners(RTCPeerConnection peerConnection) {
    final peerId = this.connection.peer;
    final connectionId = this.connection.connectionId;
    final connectionType = this.connection.type;
    final provider = this.connection.provider;

// ICE CANDIDATES.
    logger.log("Listening for ICE candidates.");

    peerConnection.onIceCandidate = (evt) {
      if (evt.candidate == null) return;

      logger.log('Received ICE candidates for ${peerId}:' + evt.candidate);

      provider.socket.send({
        'type': ServerMessageType.Candidate,
        'payload': {
          'candidate': evt.candidate,
          'type': connectionType,
          'connectionId': connectionId
        },
        'dst': peerId
      });
    };

    peerConnection.onIceConnectionState = (state) {
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          logger.log(
              "iceConnectionState is failed, closing connections to " + peerId);
          this.connection.emit(ConnectionEventType.Error,
              "Negotiation of connection to " + peerId + " failed.");
          this.connection.close();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          logger.log(
              "iceConnectionState is closed, closing connections to " + peerId);
          this.connection.emit(ConnectionEventType.Error,
              "Connection to " + peerId + " closed.");
          this.connection.close();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          logger.log(
              "iceConnectionState is disconnected, closing connections to " +
                  peerId);
          this.connection.emit(ConnectionEventType.Error,
              "Connection to " + peerId + " disconnected.");
          this.connection.close();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          peerConnection.onIceCandidate = (_) {};
          break;
        default:
          logger.log("iceConnectionState default" + peerId);
      }

      this.connection.emit(ConnectionEventType.IceStateChanged, state);
    };

// DATACONNECTION.
    logger.log("Listening for data channel");
// Fired between offer and answer, so options should already be saved
// in the options hash.
    peerConnection.onDataChannel = (evt) {
      logger.log("Received data channel");
//
//final dataChannel = evt.channel;
//const connection = <DataConnection>(
//provider.getConnection(peerId, connectionId)
//);
//
//connection.initialize(dataChannel);
    };

// MEDIACONNECTION.
    logger.log("Listening for remote stream");

    peerConnection.onAddTrack = (stream, track) {
      logger.log("Received remote stream");

      final connection = provider.getConnection(peerId, connectionId);

      if (connection.type == ConnectionType.Media) {
        MediaConnection mediaConnection = connection;

        this._addStreamToMediaConnection(stream, mediaConnection);
      }
    };
  }

  cleanup() {
    logger.log("Cleaning up PeerConnection to " + this.connection.peer);

    final peerConnection = this.connection.peerConnection;

    if (peerConnection == null) {
      return;
    }

    peerConnection.dispose();
    this.connection.peerConnection = null;

    var dataChannelNotClosed = false;

    if (dataChannelNotClosed) {
      peerConnection.close();
    }
  }

  _makeOffer() async {
    final peerConnection = this.connection.peerConnection;
    final provider = this.connection.provider;

    try {
      final offer =
          await peerConnection.createOffer(this.connection.options.constraints);

      logger.log("Created offer.");

      if (this.connection.options.sdpTransform != null &&
          this.connection.options.sdpTransform is Function) {
        offer.sdp =
            this.connection.options.sdpTransform(offer.sdp) ?? offer.sdp;
      }

      try {
        await peerConnection.setLocalDescription(offer);

        logger.log("Set localDescription:" +
            offer.toMap().toString() +
            'for:${this.connection.peer}');

        final payload = {
          'sdp': offer.toMap(),
          'type': this.connection.type,
          'connectionId': this.connection.connectionId,
          'metadata': this.connection.metadata,
        };

        provider.socket.send({
          'type': ServerMessageType.Offer,
          'payload': payload,
          'dst': this.connection.peer
        });
      } catch (err) {
// TODO: investigate why _makeOffer is being called from the answer
        if (err !=
            "OperationError: Failed to set local offer sdp: Called in wrong state: kHaveRemoteOffer") {
          provider.emitError(PeerErrorType.WebRTC, err.toString());
          logger.log("Failed to setLocalDescription, " + err.toString());
        }
      }
    } catch (err_1) {
      provider.emitError(PeerErrorType.WebRTC, err_1.toString());
      logger.log("Failed to createOffer, " + err_1.toString());
    }
  }

  _makeAnswer() async {
    final peerConnection = this.connection.peerConnection;
    final provider = this.connection.provider;

    try {
      final answer = await peerConnection.createAnswer({});
      logger.log("Created answer.");

      if (this.connection.options.sdpTransform != null &&
          this.connection.options.sdpTransform is Function) {
        answer.sdp =
            this.connection.options.sdpTransform(answer.sdp) ?? answer.sdp;
      }

      try {
        await peerConnection.setLocalDescription(answer);

        logger.log(
            'Set localDescription:`, answer, `for:${this.connection.peer}');

        provider.socket.send({
          'type': ServerMessageType.Answer,
          'payload': {
            'sdp': answer.toMap(),
            'type': this.connection.type,
            'connectionId': this.connection.connectionId,
          },
          'dst': this.connection.peer
        });
      } catch (err) {
        provider.emitError(PeerErrorType.WebRTC, err.toString());
        logger.log("Failed to setLocalDescription, " + err.toString());
      }
    } catch (err_1) {
      provider.emitError(PeerErrorType.WebRTC, err_1.toString());
      logger.log("Failed to create answer, " + err_1.toString());
    }
  }

  /** Handle an SDP. */
  handleSDP(String type, RTCSessionDescription sdp) async {
    final peerConnection = this.connection.peerConnection;
    final provider = this.connection.provider;

    logger.log("Setting remote description" + sdp.toMap().toString());

    try {
      await peerConnection.setRemoteDescription(sdp);
      logger.log('Set remoteDescription:${type} for:${this.connection.peer}');
      if (type == "OFFER") {
        await this._makeAnswer();
      }
    } catch (err) {
      provider.emitError(PeerErrorType.WebRTC, err.toString());
      logger.log("Failed to setRemoteDescription, " + err.toString());
    }
  }

  /** Handle a candidate. */
  handleCandidate(RTCIceCandidate ice) async {
    logger.log('handleCandidate:' + ice.toMap().toString());

    final peerConnection = this.connection.peerConnection;
    final provider = this.connection.provider;

    try {
      await peerConnection.addCandidate(ice);
      logger.log('Added ICE candidate for:${this.connection.peer}');
    } catch (err) {
      provider.emitError(PeerErrorType.WebRTC, err.toString());
      logger.log("Failed to handleCandidate, " + err.toString());
    }
  }

  _addTracksToConnection(MediaStream stream, RTCPeerConnection peerConnection) {
    logger.log('add tracks from stream ${stream.id} to peer connection');

    if (peerConnection.onAddTrack == null) {
      return logger.error(
          'Your browser does\'t support RTCPeerConnection#addTrack. Ignored.');
    }

//stream.getTracks().forEach(track => {
//peerConnection.addTrack(track, stream);
//});
  }

  _addStreamToMediaConnection(
      MediaStream stream, MediaConnection mediaConnection) {
    logger.log(
        'add stream ${stream.id} to media connection ${mediaConnection.connectionId}');

    mediaConnection.addStream(stream);
  }
}
