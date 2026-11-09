import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// How a member's data is laid out in their DHT "outbox" record:
/// subkey 0 holds a small JSON head, subkeys 1..[maxChunks] the gzipped
/// member JSON split into chunks. Every chunk starts with the 4-byte
/// revision it belongs to, so a reader never stitches two revisions.
class OutboxLayout {
  static const subkeys = 1 + maxChunks;
  static const maxChunks = 31;

  /// Veilid caps a subkey value at 32 KiB.
  static const chunkPayload = 32 * 1024 - 64;
}

class EncodedMember {
  EncodedMember(this.head, this.chunks);
  final Map<String, dynamic> head;
  final List<Uint8List> chunks;
}

class TooLargeException implements Exception {
  @override
  String toString() => 'Dane uczestnika są za duże do synchronizacji';
}

EncodedMember encodeMember(Map<String, dynamic> json, int rev) {
  final packed = gzip.encode(utf8.encode(jsonEncode(json)));
  final chunks = <Uint8List>[];
  for (var i = 0; i < packed.length; i += OutboxLayout.chunkPayload) {
    final end = (i + OutboxLayout.chunkPayload).clamp(0, packed.length);
    final b = BytesBuilder(copy: false)
      ..add(_u32(rev))
      ..add(packed.sublist(i, end));
    chunks.add(b.toBytes());
  }
  if (chunks.length > OutboxLayout.maxChunks) throw TooLargeException();
  return EncodedMember({
    'v': 1,
    'id': json['memberId'],
    'n': json['name'],
    'rev': rev,
    'chunks': chunks.length,
    'len': packed.length,
  }, chunks);
}

/// Rebuilds the member JSON from a head and its chunks; null when a chunk is
/// missing or from another revision (not propagated yet: try later).
Map<String, dynamic>? decodeMember(
  Map<String, dynamic> head,
  List<Uint8List?> chunks,
) {
  final rev = head['rev'] as int?;
  final n = head['chunks'] as int?;
  final len = head['len'] as int?;
  if (rev == null || n == null || len == null || chunks.length < n) {
    return null;
  }
  final b = BytesBuilder(copy: false);
  for (var i = 0; i < n; i++) {
    final c = chunks[i];
    if (c == null || c.length < 4 || _readU32(c) != rev) return null;
    b.add(Uint8List.sublistView(c, 4));
  }
  final packed = b.toBytes();
  if (packed.length != len) return null;
  try {
    return jsonDecode(utf8.decode(gzip.decode(packed))) as Map<String, dynamic>;
  } on Object {
    return null;
  }
}

Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v & 0xFFFFFFFF);

int _readU32(Uint8List b) => ByteData.sublistView(b, 0, 4).getUint32(0);
