import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'logger.dart';
import 'peer.dart';
import 'util.dart';

class API {
  final PeerOptions options;

  API(this.options);

  String _buildUrl(String method) {
    final protocol = options.secure ? "https://" : "http://";
    var url = protocol +
        options.host +
        ":" +
        options.port.toString() +
        options.path +
        options.key +
        "/" +
        method;

    final queryString = "?ts=" +
        DateTime.now().millisecondsSinceEpoch.toString() +
        "" +
        math.Random().nextInt(200).toString();
    url += queryString;

    return url;
  }

  /** Get a unique ID from the server via XHR and initialize with it. */
  Future<String> retrieveId() async {
    final url = _buildUrl("id");

    try {
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Error. Status:${response.statusCode}');
      }

      return response.body;
    } catch (error) {
      logger.error("Error retrieving ID" + error);

      var pathError = "";

      if (options.path == "/" && options.host != Util.CLOUD_HOST) {
        pathError = " If you passed in a `path` to your self-hosted PeerServer, " +
            "you'll also need to pass in that same path when creating a new " +
            "Peer.";
      }

      throw Exception("Could not get an ID from the server." + pathError);
    }
  }
}
