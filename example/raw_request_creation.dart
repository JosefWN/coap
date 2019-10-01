/*
 * Package : Coap
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 01/10/2019
 * Copyright :  S.Hamblett
 *
 * A simple discover request using .well-known/core to discover a servers resource list
 * In this example we do not use the client API to send the request message, we create and
 * perform this manually.
 */

import 'dart:async';
import 'dart:io';
import 'package:coap/coap.dart';

FutureOr<void> main(List<String> args) async {
  // Create a configuration class. Logging levels can be specified in the configuration file
  final CoapConfig conf = CoapConfig(File('example/config_all.yaml'));

  // Build the request uri, note that the request paths/query parameters can be changed
  // on the request anytime after this initial setup.
  const String host = 'coap.me';
  final Uri uri = Uri(scheme: 'coap', host: host, port: conf.defaultPort);

  // Create the client.
  // Although we are not using the client API per se we still need a client to prepare the request
  final CoapClient client = CoapClient(uri, conf);
  // You can set IPV6 here if needed using the client.addressType setter
  // Your URI above must match the scheme you chose.

  // Create the request, discovery is a get request to .well/known-core
  final CoapRequest request = CoapRequest.newGet();
  request.addUriPath(CoapConstants.defaultWellKnownURI);
  // Do anything else you need here such as setting confirmable, setting for observation etc
  //  request.markObserve();
  //  request.type = CoapMessageType.con;

  // You MUST prepare the request for transmission using the client, failing to do this will result
  // in strange behaviour, the client API does this for you.
  final CoapRequest preparedRequest = await client.prepare(request);

  // Set the request in the client
  client.request = preparedRequest;

  // Ok, ready to send, you have two ways to do this, if you want/are expecting a single response you can wait for
  // this with a specified timeout in ms. If the timeout is exceeded the response will be null, otherwise you can
  // then interrogate the response.
  final CoapResponse response =
  await preparedRequest.send().waitForResponse(30000);
  if (response != null) {
    print('EXAMPLE - response received');
    print(response.payloadString);
  } else {
    print('EXAMPLE - no response received');
  }

  // You can also listen for successive responses if you are observing, see the time_obs_resource.dart for further details.
  //  request.responses.listen((CoapResponse response) {
  //   print('EXAMPLE - payload: ${response.payloadString}');
  //  });

  // You can of course do both.

  // Clean up when complete using the client
  client.close();

  exit(0);
}
