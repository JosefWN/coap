/*
 * Package : Coap
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 08/05/2017
 * Copyright :  S.Hamblett
 */

part of coap;

/// This class describes the functionality of a CoAP endpoint resource.
abstract class CoapEndpointResource {
  /// Initialize a resource.
  CoapEndpointResource(this.name);

  /// Initialize a resource.
  CoapEndpointResource.hide(this.name, {this.hidden = true});

  /// The name of the resource identifier
  String name;

  final HashSet<CoapLinkAttribute> _attributes = HashSet<CoapLinkAttribute>();

  /// Attributes
  Iterable<CoapLinkAttribute> get attributes => _attributes;

  CoapEndpointResource? _parent;
  final SplayTreeMap<String, CoapEndpointResource> _subResources =
      SplayTreeMap<String, CoapEndpointResource>();

  /// Sub resources
  SplayTreeMap<String, CoapEndpointResource> get subResources => _subResources;

  int _totalSubResourceCount = 0;

  /// Gets the total count of sub-resources, including children
  /// and children's children...
  int get totalSubResourceCount => _totalSubResourceCount;

  /// Gets the count of sub-resources of this resource.
  int get subResourceCount => _subResources.length;

  /// Hidden
  bool hidden = false;

  /// Resource type
  String? get resourceType =>
      getAttributes(CoapLinkFormat.resourceType).firstOrNull?.valueAsString;

  set resourceType(String? value) =>
      setAttribute(CoapLinkAttribute(CoapLinkFormat.resourceType, value));

  /// Title
  String? get title =>
      getAttributes(CoapLinkFormat.title).firstOrNull?.valueAsString;

  set title(String? value) {
    clearAttribute(CoapLinkFormat.title);
    setAttribute(CoapLinkAttribute(CoapLinkFormat.resourceType, value));
  }

  /// Interface descriptions
  List<String?> get interfaceDescriptions =>
      getStringValues(getAttributes(CoapLinkFormat.interfaceDescription))
          .toList();

  /// The interface description
  String? get interfaceDescription =>
      getAttributes(CoapLinkFormat.interfaceDescription)
          .firstOrNull
          ?.valueAsString;

  set interfaceDescription(String? value) => setAttribute(
      CoapLinkAttribute(CoapLinkFormat.interfaceDescription, value));

  /// Content type codes
  List<int?> get contentTypeCodes =>
      getIntValues(getAttributes(CoapLinkFormat.contentType)).toList();

  /// The content type code
  int? get contentTypeCode =>
      getAttributes(CoapLinkFormat.contentType).firstOrNull?.valueAsInt;

  set contentTypeCode(int? value) =>
      setAttribute(CoapLinkAttribute(CoapLinkFormat.contentType, value));

  /// Maximum size estimate
  int? get maximumSizeEstimate =>
      getAttributes(CoapLinkFormat.maxSizeEstimate).firstOrNull?.valueAsInt;

  set maximumSizeEstimate(int? value) =>
      setAttribute(CoapLinkAttribute(CoapLinkFormat.maxSizeEstimate, value));

  /// Observable
  bool get observable => getAttributes(CoapLinkFormat.observable).isNotEmpty;

  set observable(bool value) {
    if (value) {
      setAttribute(CoapLinkAttribute(CoapLinkFormat.observable, value));
    } else {
      clearAttribute(CoapLinkFormat.observable);
    }
  }

  /// Resource types
  Iterable<String?> get resourceTypes =>
      getStringValues(getAttributes(CoapLinkFormat.resourceType));

  /// Gets the URI of this resource.
  String get path {
    if (_parent == null) {
      return '/$name';
    }
    var names = [name];
    for (var res = _parent; res != null; res = res._parent) {
      names.add(res.name);
    }
    return names.reversed.join('/');
  }

  /// Attributes
  List<CoapLinkAttribute> getAttributes(String name) =>
      attributes.where((CoapLinkAttribute attr) => attr.name == name).toList();

  /// Set an attribute
  bool setAttribute(CoapLinkAttribute attr) => CoapLinkFormat.addAttribute(
      attributes as HashSet<CoapLinkAttribute>,
      attr); // Adds depending on the Link Format rules

  /// Clear an attribute
  bool clearAttribute(String name) {
    var cleared = false;
    for (final attr in getAttributes(name)) {
      cleared = cleared || _attributes.remove(attr);
    }
    return cleared;
  }

  /// Get string values
  static Iterable<String?> getStringValues(
      Iterable<CoapLinkAttribute> attributes) {
    final list = <String?>[];
    for (final attr in attributes) {
      list.add(attr.valueAsString);
    }
    return list;
  }

  /// Get integer values
  static Iterable<int?> getIntValues(Iterable<CoapLinkAttribute> attributes) {
    final list = <int?>[];
    for (final attr in attributes) {
      list.add(attr.valueAsInt);
    }
    return list;
  }

  /// Removes this resource from its parent.
  void remove() {
    if (_parent != null) {
      _parent!.removeSubResource(this);
    }
  }

  /// Gets sub-resources of this resource.
  List<CoapEndpointResource> getSubResources() {
    final resources = <CoapEndpointResource>[];
    resources.addAll(_subResources.values);
    return resources;
  }

  /// Removes a sub-resource from this resource.
  void removeSubResource(CoapEndpointResource? resource) {
    if (resource == null) {
      return;
    }
    if (_subResources.remove(resource.name) != null) {
      var p = resource._parent;
      while (p != null) {
        p._totalSubResourceCount--;
        p = p._parent;
      }

      resource._parent = null;
    }
  }

  /// Resource path
  CoapEndpointResource? getResourcePath(String? path) =>
      getResource(path, last: false);

  /// Resources
  CoapEndpointResource? getResource(String? path, {bool? last}) {
    if (path == null || path.isEmpty) {
      return this;
    }
    // find root for absolute path
    if (path.startsWith('/')) {
      var root = this;
      while (root._parent != null) {
        root = root._parent!;
      }
      final path1 = path == '/' ? null : path.substring(1);
      return root.getResourcePath(path1);
    }

    final pos = path.indexOf('/');
    String? head, tail;

    // note: 'some/resource/' addresses a resource '' under 'resource'
    if (pos == -1) {
      head = path;
    } else {
      head = path.substring(0, pos);
      tail = path.substring(pos + 1);
    }

    if (_subResources.containsKey(head)) {
      return _subResources[head]!.getResource(tail, last: last);
    } else if (last!) {
      return this;
    } else {
      return null;
    }
  }

  /// Adds a resource as a sub-resource of this resource.
  void addSubResource(CoapEndpointResource resource) {
    // no absolute paths allowed, use root directly
    while (resource.name.startsWith('/')) {
      resource.name = resource.name.substring(1);
    }

    // Get last existing resource along path
    var baseRes = getResource(resource.name, last: true)!;

    var path = this.path;
    if (!path.endsWith('/')) {
      path += '/';
    }
    path += resource.name;

    path = path.substring(baseRes.path.length);
    if (path.startsWith('/')) {
      path = path.substring(1);
    }

    if (path.isEmpty) {
      // resource replaces base
      for (final sub in baseRes.getSubResources()) {
        sub._parent = resource;
        resource.subResources[sub.name] = sub;
      }
      resource._parent = baseRes._parent;
      baseRes._parent!.subResources[baseRes.name] = resource;
    } else {
      // resource is added to base

      final segments = path.split('/');
      if (segments.length > 1) {
        resource.name = segments[segments.length - 1];

        // insert middle segments
        CoapEndpointResource sub;
        for (var i = 0; i < segments.length - 1; i++) {
          sub = baseRes.createInstance(segments[i]);
          sub.hidden = true;
          baseRes.addSubResource(sub);
          baseRes = sub;
        }
      } else {
        resource.name = path;
      }

      resource._parent = baseRes;
      baseRes.subResources[resource.name] = resource;
    }

    // update number of sub-resources in the tree
    var p = resource._parent;
    while (p != null) {
      p._totalSubResourceCount++;
      p = p._parent;
    }
  }

  /// Removes a sub-resource from this resource by its identifier.
  void removeSubResourcePath(String resourcePath) {
    removeSubResource(getResourcePath(resourcePath));
  }

  /// Create a sub resource
  void createSubResource(CoapRequest request, String newIdentifier) {
    doCreateSubResource(request, newIdentifier);
  }

  /// Creates a resouce instance with proper subtype.
  CoapEndpointResource createInstance(String name);

  /// Create sub resource helper
  void doCreateSubResource(CoapRequest request, String newIdentifier);
}
