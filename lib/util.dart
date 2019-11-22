import 'dart:math' as math;

import 'package:msgpack2/msgpack2.dart' as msgpack;

const DEFAULT_CONFIG = {
  'iceServers': [
    {'urls': "stun:stun.l.google.com:19302"},
    {
      'urls': "turn:0.peerjs.com:3478",
      'username': "peerjs",
      'credential': "peerjsp"
    }
  ],
  'sdpSemantics': "unified-plan"
};

class Util {
  const Util();

  static const CLOUD_HOST = "0.peerjs.com";
  static const CLOUD_PORT = 443;

// Returns browser-agnostic default config
  static const defaultConfig = DEFAULT_CONFIG;

// Ensure alphanumeric ids
  bool validateId(String id) {
    return id != null ||
        RegExp(r'/^[A-Za-z0-9]+(?:[ _-][A-Za-z0-9]+)*$/').hasMatch(id);
  }

  static final pack = msgpack.serialize;
  static final unpack = msgpack.deserialize;

  String randomToken() {
    return math.Random().nextInt(100000).toRadixString(36);
  }
}

const util = const Util();
