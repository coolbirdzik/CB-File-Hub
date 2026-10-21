import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cb_native/cb_native.dart';
import 'package:test/test.dart';

/// A one-page PDF showing [text] in Helvetica, with a correct xref table.
List<int> pdf(String text) {
  final content = 'BT /F1 12 Tf 72 720 Td ($text) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding /WinAnsiEncoding >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return latin1.encode(out.toString());
}

List<int> zip(Map<String, String> entries) {
  final archive = Archive();
  entries.forEach(
    (name, text) => archive.add(ArchiveFile.bytes(name, utf8.encode(text))),
  );
  return ZipEncoder().encode(archive);
}

void main() {
  final skip = CbNative.isAvailable ? null : 'Rust library not built';
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cb_native_content_');
  });
  tearDown(() => root.delete(recursive: true));

  void write(String name, List<int> bytes) {
    File('${root.path}/$name')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  String name(String path) => path.split(RegExp(r'[\\/]')).last;

  test('finds words in text, Office and PDF files', () async {
    write('invoice.pdf', pdf('Hoa don tien dien thang 9'));
    write(
      'sub/report.docx',
      zip({
        'word/document.xml':
            '<w:p><w:r><w:t>Báo cáo tiền điện</w:t></w:r></w:p>',
      }),
    );
    write('notes.txt', utf8.encode('tiền nước'));
    write('legacy.doc', utf8.encode('tien dien'));
    write('scan.pdf', utf8.encode('%PDF-1.4 no text layer'));

    final result = await NativeContent.search(
      root: root.path,
      terms: ['tien', 'dien'],
    );
    expect(result!.finished, true);
    expect(result.matches.map((m) => name(m.path)).toSet(), {
      'invoice.pdf',
      'report.docx',
    });
    final invoice = result.matches.firstWhere((m) => m.format == 'pdf');
    expect(invoice.matchedTerms, [0, 1]);
    expect(invoice.snippets.single.$2, 'Hoa don tien dien thang 9');
    expect(result.filesSearched, 3);
    expect(result.noText, 1);
    expect(result.unsupported, {'.doc': 1});
    expect(result.stop, NativeContentStop.none);

    final any = await NativeContent.search(
      root: root.path,
      terms: ['nuoc', 'dien'],
      matchAll: false,
    );
    expect(any!.matches, hasLength(3));
  }, skip: skip);

  test('documentText returns PDF text and null for an empty file', () async {
    write('a.pdf', pdf('Bien ban hop'));
    write('blank.pdf', utf8.encode('%PDF-1.4 broken'));
    final text = await NativeContent.documentText('${root.path}/a.pdf', 'pdf');
    expect(text!.text!.trim(), 'Bien ban hop');
    final blank = await NativeContent.documentText(
      '${root.path}/blank.pdf',
      'pdf',
    );
    expect(blank!.text, isNull);
  }, skip: skip);
}
