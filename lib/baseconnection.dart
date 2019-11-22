import 'package:eventify/eventify.dart';
import 'package:flutter_webrtc/webrtc.dart';

import 'peer.dart';
import 'servermessage.dart';

abstract class BaseConnection extends EventEmitter {
  var open = false;

  dynamic metadata;
  String connectionId;
  final String peer;
  final Peer provider;
  final PeerConnectOption options;

  RTCPeerConnection peerConnection;

  String get type;

  BaseConnection(this.peer, this.provider, this.options) {
    this.metadata = options.metadata;
  }

  close();

  handleMessage(ServerMessage message);
}
