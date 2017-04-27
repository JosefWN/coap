/*
 * Package : Coap
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 27/04/2017
 * Copyright :  S.Hamblett
 */

part of coap;

class CoapConfig extends config.ConfigurationItem {
  CoapConfig(String filename) : super.fromFile(filename);

  /// The version of the CoAP protocol.
  @config.optionalConfiguration
  String version = "RFC7252";

  /// The default CoAP port for normal CoAP communication (not secure).
  int defaultPort = CoapConstants.defaultPort;

  /// The default CoAP port for secure CoAP communication (coaps).
  int defaultSecurePort = CoapConstants.defaultSecurePort;

  /// The port which HTTP proxy is on.
  int httpPort = 8080;

  /// The initial time (ms) for a CoAP message
  int ackTimeout = CoapConstants.ackTimeout;


}
