/*
 * Package : Coap
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 06/06/2018
 * Copyright :  S.Hamblett
 *
 * A request for the hello world test server resource
 */

import 'dart:async';
import 'package:coap/coap.dart';
import 'config/coap_config.dart';

FutureOr<void> main(List<String> args) async {
  // Create a configuration class. Logging levels can be specified in
  // the configuration file
  final conf = CoapConfig();

  // Build the request uri, note that the request paths/query parameters can be changed
  // on the request anytime after this initial setup.
  const host = 'coap.me';

  final uri = Uri(scheme: 'coap', host: host, port: conf.defaultPort);

  // Create the client.
  // The method we are using creates its own request so we do not
  // need to supply one.
  // The current request is always available from the client.
  final client = CoapClient(uri, conf);

  // Adjust the response timeout if needed, defaults to 32767 milliseconds
  //client.timeout = 10000;

  // Create the request for the get request
  final request = CoapRequest.newGet();
  request.addUriPath('hello');
  client.request = request;

  print('EXAMPLE - Sending get request to $host, waiting for response....');

  final response = await client.get();
  print('EXAMPLE - response received');
  print(response.payloadString);

  // Clean up
  client.close();
}
