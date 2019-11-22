class ConnectionEventType {
  static final Open = "open";
  static final Stream = "stream";
  static final Data = "data";
  static final Close = "close";
  static final Error = "error";
  static final IceStateChanged = "iceStateChanged";
}

class ConnectionType {
  static final Data = "data";
  static final Media = "media";
}

class PeerEventType {
  static final Open = "open";
  static final Close = "close";
  static final Connection = "connection";
  static final Call = "call";
  static final Disconnected = "disconnected";
  static final Error = "error";
}

class PeerErrorType {
  static final BrowserIncompatible = "browser-incompatible";
  static final Disconnected = "disconnected";
  static final InvalidID = "invalid-id";
  static final InvalidKey = "invalid-key";
  static final Network = "network";
  static final PeerUnavailable = "peer-unavailable";
  static final SslUnavailable = "ssl-unavailable";
  static final ServerError = "server-error";
  static final SocketError = "socket-error";
  static final SocketClosed = "socket-closed";
  static final UnavailableID = "unavailable-id";
  static final WebRTC = "webrtc";
}

class SerializationType {
  static final Binary = "binary";
  static final BinaryUTF8 = "binary-utf8";
  static final JSON = "json";
}

class SocketEventType {
  static final Message = "message";
  static final Disconnected = "disconnected";
  static final Error = "error";
  static final Close = "close";
}

class ServerMessageType {
  static final Heartbeat = "HEARTBEAT";
  static final Candidate = "CANDIDATE";
  static final Offer = "OFFER";
  static final Answer = "ANSWER";
  static final Open = "OPEN";
  static final Error = "ERROR";
  static final IdTaken = "ID-TAKEN";
  static final InvalidKey = "INVALID-KEY";
  static final Leave = "LEAVE";
  static final Expire = "EXPIRE";
}
