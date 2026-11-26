import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// The native calls that build a `.gfpd` audio graph (gfpa_graph.h).
///
/// The same symbols live in `libdart_vst_host` on desktop and in
/// `libnative-lib.so` on Android; [GfpaGraphApi.new] binds them from
/// whichever library the caller passes.
class GfpaGraphApi {
  /// Binds the builder calls from [lib].
  GfpaGraphApi(DynamicLibrary lib)
      : _begin = lib.lookupFunction<Pointer<Void> Function(Int32, Int32),
            Pointer<Void> Function(int, int)>('gfpa_graph_begin'),
        _addNode = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
            int Function(Pointer<Void>, Pointer<Utf8>,
                Pointer<Utf8>)>('gfpa_graph_add_node'),
        _connect = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>,
                Pointer<Utf8>, Pointer<Utf8>),
            int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>,
                Pointer<Utf8>, Pointer<Utf8>)>('gfpa_graph_connect'),
        _addParam = lib.lookupFunction<
            Int32 Function(
                Pointer<Void>, Pointer<Utf8>, Double, Double, Double),
            int Function(Pointer<Void>, Pointer<Utf8>, double, double,
                double)>('gfpa_graph_add_param'),
        _bind = lib.lookupFunction<
            Int32 Function(
                Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
            int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>,
                Pointer<Utf8>)>('gfpa_graph_bind'),
        _setConst = lib.lookupFunction<
            Int32 Function(
                Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Double),
            int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>,
                double)>('gfpa_graph_set_const'),
        _finish = lib.lookupFunction<Pointer<Void> Function(Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>)>('gfpa_graph_finish'),
        _abort = lib.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('gfpa_graph_abort');

  final Pointer<Void> Function(int, int) _begin;
  final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) _addNode;
  final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>,
      Pointer<Utf8>, Pointer<Utf8>) _connect;
  final int Function(Pointer<Void>, Pointer<Utf8>, double, double, double)
      _addParam;
  final int Function(
      Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>) _bind;
  final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, double)
      _setConst;
  final Pointer<Void> Function(Pointer<Void>) _finish;
  final void Function(Pointer<Void>) _abort;
}

/// Builds the native effect for [descriptor]'s `graph:` section and returns
/// its handle, which the host then treats like a built-in effect's.
///
/// Returns [nullptr] when the descriptor is not an audio effect, has no
/// graph, or describes one the native side cannot run (an unknown node type
/// or port, a loop, no `audio_out`). The failing step is logged, so a plugin
/// author running from a terminal can see what to fix.
Pointer<Void> buildGfpaGraph(
  GfpaGraphApi api,
  GFPluginDescriptor descriptor, {
  required int sampleRate,
  required int blockSize,
}) {
  if (descriptor.type != GFPluginType.effect || descriptor.nodes.isEmpty) {
    return nullptr;
  }
  final builder = api._begin(sampleRate, blockSize);
  if (builder == nullptr) return nullptr;
  final failure = using((arena) {
    Pointer<Utf8> s(String text) => text.toNativeUtf8(allocator: arena);
    return _describe(api, builder, descriptor, s);
  });
  if (failure != null) {
    api._abort(builder);
    debugPrint('gfpd graph "${descriptor.id}": $failure');
    return nullptr;
  }
  final handle = api._finish(builder);
  if (handle == nullptr) {
    debugPrint('gfpd graph "${descriptor.id}": needs exactly one audio_out, '
        'at most one audio_in, and no loop');
  }
  return handle;
}

/// Sends [d]'s nodes, wires and parameters to [builder], in that order (a
/// wire or a binding names nodes, so the nodes come first). Returns null on
/// success, or what went wrong.
String? _describe(
  GfpaGraphApi api,
  Pointer<Void> builder,
  GFPluginDescriptor d,
  Pointer<Utf8> Function(String) s,
) {
  for (final node in d.nodes) {
    if (api._addNode(builder, s(node.id), s(node.type)) != 0) {
      return 'unknown node type "${node.type}" (node "${node.id}")';
    }
  }
  for (final c in d.connections) {
    final code = api._connect(
        builder, s(c.fromNode), s(c.fromPort), s(c.toNode), s(c.toPort));
    if (code != 0) {
      return 'cannot connect ${c.fromNode}.${c.fromPort} to '
          '${c.toNode}.${c.toPort}';
    }
  }
  for (final p in d.parameters) {
    api._addParam(builder, s(p.id), p.min, p.max, p.defaultValue);
  }
  return _describeBindings(api, builder, d, s);
}

/// Sends every `{ param: id }` and `{ value: n }` of [d]'s nodes.
String? _describeBindings(
  GfpaGraphApi api,
  Pointer<Void> builder,
  GFPluginDescriptor d,
  Pointer<Utf8> Function(String) s,
) {
  for (final node in d.nodes) {
    for (final MapEntry(key: name, value: binding) in node.params.entries) {
      final code = switch (binding) {
        GFParamRefBinding(:final paramId) =>
          api._bind(builder, s(paramId), s(node.id), s(name)),
        GFConstantBinding(:final value) =>
          api._setConst(builder, s(node.id), s(name), value),
      };
      if (code != 0) {
        return 'node "${node.id}" has no parameter "$name", '
            'or it is bound to an undeclared plugin parameter';
      }
    }
  }
  return null;
}
