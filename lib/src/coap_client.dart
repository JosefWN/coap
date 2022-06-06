/*
 * Package : Coap
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 05/06/2018
 * Copyright :  S.Hamblett
 */

import 'dart:async';
import 'dart:io';

import 'package:coap/src/exceptions/coap_request_exception.dart';
import 'package:collection/collection.dart';
import 'package:synchronized/synchronized.dart';
import 'package:typed_data/typed_data.dart';

import 'coap_block_option.dart';
import 'coap_code.dart';
import 'coap_config.dart';
import 'coap_constants.dart';
import 'coap_link_format.dart';
import 'coap_media_type.dart';
import 'coap_message.dart';
import 'coap_message_type.dart';
import 'coap_observe_client_relation.dart';
import 'coap_option.dart';
import 'coap_option_type.dart';
import 'coap_request.dart';
import 'coap_response.dart';
import 'coap_web_link.dart';
import 'event/coap_event_bus.dart';
import 'net/coap_endpoint.dart';
import 'net/coap_iendpoint.dart';
import 'net/coap_internet_address.dart';
import 'network/coap_inetwork.dart';
import 'network/credentials/ecdsa_keys.dart';
import 'network/credentials/psk_credentials.dart';

/// The matching scheme to use for supplied ETags on PUT
enum MatchEtags {
  /// When the ETag matches
  onMatch,

  /// When none of the ETag matches
  onNoneMatch,
}

/// Response event handler for multicast responses
class CoapMulticastResponseHandler {
  final void Function(CoapRespondEvent)? onData;
  final Function? onError;
  final void Function()? onDone;
  final bool? cancelOnError;

  CoapMulticastResponseHandler(this.onData,
      {this.onError, this.onDone, this.cancelOnError});
}

/// Provides convenient methods for accessing CoAP resources.
/// This class provides a fairly high level interface for the majority of
/// simple CoAP requests but because of this is fairly coarsely grained.
/// Much finer control of a request can be achieved by direct construction
/// and manipulation of a CoapRequest itself, however this is more involved,
/// for most cases the API in this class should suffice.
///
/// Note that currently a self constructed resource must be prepared
/// by the prepare method in this class BEFORE calling any send
/// methods on the resource.
///
/// In most cases a resource can be created outside of the client with
/// the relevant parameters then set in the client.
class CoapClient {
  /// Instantiates.
  /// A supplied request is optional depending on the API call being used.
  /// If it is specified it will be prepared and used.
  /// Note that the host name part of the URI can be a name or an IP address,
  /// in which case it is not resolved.
  CoapClient(
    this.uri,
    this._config, {
    this.addressType = InternetAddressType.IPv4,
    this.bindAddress,
    EcdsaKeys? ecdsaKeys,
    PskCredentialsCallback? pskCredentialsCallback,
  })  : _ecdsaKeys = ecdsaKeys,
        _pskCredentialsCallback = pskCredentialsCallback {
    _eventBus = CoapEventBus(namespace: hashCode.toString());
  }

  /// Address type used for DNS lookups.
  final InternetAddressType addressType;

  /// The client's local socket bind address, if set explicitly
  /// IPv4 default is 0.0.0.0, IPv6 default is 0:0:0:0:0:0:0:0
  final InternetAddress? bindAddress;

  /// The client endpoint URI
  final Uri uri;

  late final CoapEventBus _eventBus;

  /// The internal request/response event stream
  CoapEventBus get events => _eventBus;

  final DefaultCoapConfig _config;
  CoapIEndPoint? _endpoint;
  final _lock = Lock();

  /// Raw Public Keys for CoAPS with tinyDtls.
  final EcdsaKeys? _ecdsaKeys;

  /// Callback for providing [PskCredentials] (combination of a Pre-shared Key
  /// and an Identity) for DTLS, optionally based on an Identity Hint.
  final PskCredentialsCallback? _pskCredentialsCallback;

  /// Performs a CoAP ping.
  Future<bool> ping() async {
    final request = CoapRequest(CoapCode.empty, confirmable: true);
    request.token = CoapConstants.emptyToken;
    await _prepare(request);
    _endpoint!.sendEpRequest(request);
    await _waitForReject(request);
    return request.isRejected;
  }

  /// Sends a GET request.
  Future<CoapResponse> get(
    String path, {
    int accept = CoapMediaType.textPlain,
    int type = CoapMessageType.con,
    List<CoapOption>? options,
    bool earlyBlock2Negotiation = false,
    int maxRetransmit = 0,
    CoapMulticastResponseHandler? onMulticastResponse,
  }) {
    final request = CoapRequest.newGet();
    _build(request, path, accept, type, options, earlyBlock2Negotiation,
        maxRetransmit);
    return send(request, onMulticastResponse: onMulticastResponse);
  }

  /// Sends a POST request.
  Future<CoapResponse> post(
    String path, {
    required String payload,
    int format = CoapMediaType.textPlain,
    int accept = CoapMediaType.textPlain,
    int type = CoapMessageType.con,
    List<CoapOption>? options,
    bool earlyBlock2Negotiation = false,
    int maxRetransmit = 0,
    CoapMulticastResponseHandler? onMulticastResponse,
  }) {
    final request = CoapRequest.newPost()..setPayloadMedia(payload, format);
    _build(request, path, accept, type, options, earlyBlock2Negotiation,
        maxRetransmit);
    return send(request, onMulticastResponse: onMulticastResponse);
  }

  /// Sends a POST request with the specified byte payload.
  Future<CoapResponse> postBytes(
    String path, {
    required Uint8Buffer payload,
    int format = CoapMediaType.textPlain,
    int accept = CoapMediaType.textPlain,
    int type = CoapMessageType.con,
    List<CoapOption>? options,
    bool earlyBlock2Negotiation = false,
    int maxRetransmit = 0,
    CoapMulticastResponseHandler? onMulticastResponse,
  }) {
    final request = CoapRequest.newPost()..setPayloadMediaRaw(payload, format);
    _build(request, path, accept, type, options, earlyBlock2Negotiation,
        maxRetransmit);
    return send(request, onMulticastResponse: onMulticastResponse);
  }

  /// Sends a PUT request.
  Future<CoapResponse> put(
    String path, {
    required String payload,
    int format = CoapMediaType.textPlain,
    int accept = CoapMediaType.textPlain,
    int type = CoapMessageType.con,
    List<Uint8Buffer>? etags,
    MatchEtags matchEtags = MatchEtags.onMatch,
    List<CoapOption>? options,
    bool earlyBlock2Negotiation = false,
    int maxRetransmit = 0,
    CoapMulticastResponseHandler? onMulticastResponse,
  }) {
    final request = CoapRequest.newPut()..setPayloadMedia(payload, format);
    _build(request, path, accept, type, options, earlyBlock2Negotiation,
        maxRetransmit,
        etags: etags, matchEtags: matchEtags);
    return send(request, onMulticastResponse: onMulticastResponse);
  }

  /// Sends a PUT request with the specified byte payload.
  Future<CoapResponse> putBytes(
    String path, {
    required Uint8Buffer payload,
    int format = CoapMediaType.textPlain,
    MatchEtags matchEtags = MatchEtags.onMatch,
    List<Uint8Buffer>? etags,
    int accept = CoapMediaType.textPlain,
    int type = CoapMessageType.con,
    List<CoapOption>? options,
    bool earlyBlock2Negotiation = false,
    int maxRetransmit = 0,
    CoapMulticastResponseHandler? onMulticastResponse,
  }) {
    final request = CoapRequest.newPut()..setPayloadMediaRaw(payload, format);
    _build(request, path, accept, type, options, earlyBlock2Negotiation,
        maxRetransmit,
        etags: etags, matchEtags: matchEtags);
    return send(request, onMulticastResponse: onMulticastResponse);
  }

  /// Sends a DELETE request
  Future<CoapResponse> delete(
    String path, {
    int accept = CoapMediaType.textPlain,
    int type = CoapMessageType.con,
    List<CoapOption>? options,
    bool earlyBlock2Negotiation = false,
    int maxRetransmit = 0,
    CoapMulticastResponseHandler? onMulticastResponse,
  }) {
    final request = CoapRequest.newDelete();
    _build(request, path, accept, type, options, earlyBlock2Negotiation,
        maxRetransmit);
    return send(request, onMulticastResponse: onMulticastResponse);
  }

  /// Observe
  Future<CoapObserveClientRelation> observe(
    CoapRequest request, {
    int maxRetransmit = 0,
  }) async {
    request
      ..observe = 0
      ..maxRetransmit = maxRetransmit;
    await _prepare(request);
    final relation = CoapObserveClientRelation(request);
    unawaited(() async {
      _endpoint!.sendEpRequest(request);
      final resp = await _waitForResponse(request);
      if (!resp.hasOption(OptionType.observe)) {
        relation.isCancelled = true;
      }
    }());
    return relation;
  }

  /// Discovers remote resources.
  Future<Iterable<CoapWebLink>?> discover({
    String query = '',
  }) async {
    final discover = CoapRequest.newGet()
      ..uriPath = CoapConstants.defaultWellKnownURI;
    if (query.isNotEmpty) {
      discover.uriQuery = query;
    }
    final links = await send(discover);
    if (links.contentFormat != CoapMediaType.applicationLinkFormat) {
      return <CoapWebLink>[CoapWebLink('')];
    } else {
      return CoapLinkFormat.parse(links.payloadString!);
    }
  }

  /// Send
  Future<CoapResponse> send(
    CoapRequest request, {
    CoapMulticastResponseHandler? onMulticastResponse,
  }) async {
    await _prepare(request);
    if (request.isMulticast) {
      if (onMulticastResponse == null) {
        throw ArgumentError('Missing onMulticastResponse argument');
      }
      _eventBus
          .on<CoapRespondEvent>()
          .where((CoapRespondEvent e) => e.resp.token!.equals(request.token!))
          .takeWhile((_) => !request.isTimedOut && !request.isCancelled)
          .listen(
            onMulticastResponse.onData,
            onError: onMulticastResponse.onError,
            onDone: onMulticastResponse.onDone,
            cancelOnError: onMulticastResponse.cancelOnError,
          );
    }
    _endpoint!.sendEpRequest(request);
    return _waitForResponse(request);
  }

  /// Cancel ongoing observable request
  Future<void> cancelObserveProactive(
      CoapObserveClientRelation relation) async {
    final cancel = relation.newCancel();
    await send(cancel);
    relation.isCancelled = true;
  }

  /// Cancel after the fact
  void cancelObserveReactive(CoapObserveClientRelation relation) {
    relation.isCancelled = true;
  }

  /// Cancels a request
  void cancel(CoapRequest request) {
    request.isCancelled = true;
    final response = CoapResponse(CoapCode.empty)
      ..id = request.id
      ..token = request.token;
    _eventBus.fire(CoapRespondEvent(response));
  }

  /// Cancel all ongoing requests
  void close() {
    _endpoint?.stop();
  }

  void _build(
    CoapRequest request,
    String path,
    int accept,
    int type,
    List<CoapOption>? options,
    bool earlyBlock2Negotiation,
    int maxRetransmit, {
    MatchEtags matchEtags = MatchEtags.onMatch,
    List<Uint8Buffer>? etags,
  }) {
    request
      ..addUriPath(path)
      ..accept = accept
      ..type = type
      ..maxRetransmit = maxRetransmit;
    if (options != null) {
      request.addOptions(options);
    }
    if (etags != null) {
      switch (matchEtags) {
        case MatchEtags.onMatch:
          etags.forEach(request.addIfMatchOpaque);
          break;
        case MatchEtags.onNoneMatch:
          etags.forEach(request.addIfNoneMatchOpaque);
      }
    }
    if (earlyBlock2Negotiation) {
      request.setBlock2(
          CoapBlockOption.encodeSZX(_config.preferredBlockSize), 0,
          m: false);
    }
  }

  Future<void> _prepare(CoapRequest request) async {
    request.uri = uri;
    request.timestamp = DateTime.now();
    request.setEventBus(_eventBus);

    // Set a default accept
    if (request.accept == CoapMediaType.undefined) {
      request.accept = CoapMediaType.textPlain;
    }

    await _lock.synchronized(() async {
      // Set endpoint if missing
      if (_endpoint == null) {
        final destination =
            await _lookupHost(uri.host, addressType, bindAddress);
        final socket = CoapINetwork.fromUri(uri,
            address: destination,
            config: _config,
            namespace: _eventBus.namespace,
            pskCredentialsCallback: _pskCredentialsCallback,
            ecdsaKeys: _ecdsaKeys);
        await socket.bind();
        _endpoint =
            CoapEndPoint(socket, _config, namespace: _eventBus.namespace);
        await _endpoint!.start();
      }
    });

    request.endpoint = _endpoint;
  }

  Future<CoapInternetAddress> _lookupHost(String host,
      InternetAddressType addressType, InternetAddress? bindAddress) async {
    final parsedAddress = InternetAddress.tryParse(host);
    if (parsedAddress != null) {
      return CoapInternetAddress(
          parsedAddress.type, parsedAddress, bindAddress);
    }

    final addresses = await InternetAddress.lookup(host, type: addressType);
    if (addresses.isNotEmpty) {
      return CoapInternetAddress(addressType, addresses[0], bindAddress);
    }

    throw SocketException("Failed host lookup: '$host'");
  }

  /// Wait for a response.
  /// Returns the response, or null if timeout occured.
  Future<CoapResponse> _waitForResponse(CoapRequest req) {
    final completer = Completer<CoapResponse>();
    _eventBus
        .on<CoapRespondEvent>()
        .where((CoapRespondEvent e) => e.resp.token!.equals(req.token!))
        .take(1)
        .listen((CoapRespondEvent e) {
      if (req.isTimedOut) {
        completer.completeError(CoapRequestTimeoutException(req.retransmits));
      } else if (req.isCancelled) {
        completer.completeError(CoapRequestCancellationException());
      } else {
        e.resp.timestamp = DateTime.now();
        completer.complete(e.resp);
      }
    });
    return completer.future;
  }

  /// Wait for a reject.
  /// Returns the rejected message, or null if timeout occured.
  Future<CoapMessage?> _waitForReject(CoapRequest req) {
    final completer = Completer<CoapMessage?>();
    _eventBus
        .on<CoapRejectedEvent>()
        .where((CoapRejectedEvent e) => e.msg.id == req.id)
        .take(1)
        .listen((CoapRejectedEvent e) {
      if (req.isTimedOut || req.isCancelled) {
        completer.complete(null);
      } else {
        e.msg.timestamp = DateTime.now();
        completer.complete(e.msg);
      }
    });
    return completer.future;
  }
}
