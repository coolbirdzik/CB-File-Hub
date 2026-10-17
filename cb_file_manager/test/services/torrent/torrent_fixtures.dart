import 'dart:convert';
import 'dart:typed_data';

List<int> bencode(Object value) {
  if (value is String) return bencode(Uint8List.fromList(utf8.encode(value)));
  if (value is Uint8List) {
    return [...ascii.encode('${value.length}:'), ...value];
  }
  if (value is int) return ascii.encode('i${value}e');
  if (value is List) {
    return [108, ...value.expand((v) => bencode(v as Object)), 101];
  }
  if (value is Map<String, Object>) {
    return [
      100,
      for (final entry in value.entries) ...[
        ...bencode(entry.key),
        ...bencode(entry.value),
      ],
      101,
    ];
  }
  throw ArgumentError.value(value);
}

Map<String, Object> torrentInfo({String name = 'example.mp4', int size = 4}) =>
    {
      'name': name,
      'length': size,
      'piece length': 16384,
      'pieces': Uint8List(((size + 16383) ~/ 16384) * 20),
    };

Uint8List torrentBytes({
  String name = 'example.mp4',
  String? tracker,
  Map<String, Object>? info,
}) => Uint8List.fromList(
  bencode({'announce': ?tracker, 'info': info ?? torrentInfo(name: name)}),
);
