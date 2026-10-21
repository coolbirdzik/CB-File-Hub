import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cb_file_manager/helpers/core/text_utils.dart';
import 'package:cb_file_manager/services/ai/content_search.dart';
import 'package:cb_file_manager/services/ai/document_text.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
  for (final entry in entries.entries) {
    archive.add(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
  }
  return ZipEncoder().encode(archive);
}

/// Documents of every format both searches read.
Map<String, List<int>> documents() {
  final bs = String.fromCharCode(92);
  return {
    'invoice.docx': zip({
      'word/document.xml':
          '<w:document><w:body><w:p><w:r><w:t>Hóa đơn tiền điện</w:t></w:r>'
          '</w:p><w:p><w:r><w:t>Tháng 9 &amp; tháng 10</w:t></w:r></w:p>'
          '</w:body></w:document>',
      'word/footer1.xml': '<w:ftr><w:p><w:t>Trang 1</w:t></w:p></w:ftr>',
      'word/styles.xml': '<w:styles><w:t>hoa don tien dien</w:t></w:styles>',
    }),
    'budget.xlsx': zip({
      'xl/sharedStrings.xml':
          '<sst><si><t>Ngân sách</t></si><si><t>Điện nước</t></si></sst>',
      'xl/worksheets/sheet1.xml':
          '<worksheet><c t="inlineStr"><is><t>Tiền điện quý 3</t></is></c>'
          '<c><v>42</v></c></worksheet>',
    }),
    'deck.pptx': zip({
      'ppt/slides/slide2.xml': '<p:sld><a:p><a:t>Second</a:t></a:p></p:sld>',
      'ppt/slides/slide10.xml':
          '<p:sld><a:p><a:t>Tiền điện</a:t></a:p></p:sld>',
    }),
    'notes.odt': zip({
      'content.xml':
          '<office:text><text:p>Ghi chú tiền điện</text:p>'
          '<text:p>dòng<text:tab/>hai</text:p></office:text>',
    }),
    'book.epub': zip({
      'OEBPS/ch1.xhtml':
          '<html><body><script>tien dien</script><p>Không liên quan</p>'
          '<p>Tiền&#x20;điện &#999999999; cuối</p></body></html>',
    }),
    'letter.rtf': utf8.encode(
      '{${bs}rtf1{${bs}fonttbl{${bs}f0 Arial;}}${bs}f0 Ti${bs}u7873?n '
      '${bs}u273?i${bs}u7879?n${bs}par a$bs{b$bs}c}',
    ),
    'plain.txt': utf8.encode(
      'Dòng một\r\n\r\n  tiền   điện  tháng 9  \n${'x ' * 150}tien dien'
      '${' y' * 150}',
    ),
    'utf16.txt': [
      0xFF,
      0xFE,
      for (final unit in 'Biên bản tiền điện'.codeUnits) ...[
        unit & 0xFF,
        unit >> 8,
      ],
    ],
    'binary.txt': [0, 1, 2, 3],
  };
}

void main() {
  final nativeSkip = CbNative.isAvailable ? null : 'Rust library not built';
  late Directory sandbox;
  late ToolExecutor executor;
  var cancelled = false;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('cb-agent-content-');
    cancelled = false;
    executor = ToolExecutor()
      ..beginTurn(currentPath: sandbox.path, isCancelled: () => cancelled);
  });
  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  Future<Map<String, dynamic>> run(
    String name,
    Map<String, dynamic> args,
  ) async {
    final result = await executor.execute(
      ToolCall(name: name, arguments: args),
    );
    expect(result.success, true, reason: result.output);
    return jsonDecode(result.output) as Map<String, dynamic>;
  }

  File write(String name, List<int> bytes) => File(p.join(sandbox.path, name))
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  Future<ContentSearchOutcome> search(
    String query, {
    required bool useNative,
    bool matchAll = true,
  }) => ContentSearch.run(
    ContentSearchRequest(root: sandbox.path, query: query, matchAll: matchAll),
    isCancelled: () => false,
    useNative: useNative,
  );

  List<String> names(Iterable<dynamic> items) => [
    for (final item in items) item['name'] as String,
  ];

  for (final useNative in [true, false]) {
    final backend = useNative ? 'native' : 'Dart';
    final skip = useNative ? nativeSkip : null;

    group('$backend search', () {
      test('words match anywhere, ignoring case and diacritics', () async {
        write(
          'hop-dong.txt',
          utf8.encode('HỢP ĐỒNG thuê nhà\n\nBên B: Công ty ABC\nGiá: 5'),
        );
        write('abc-only.txt', utf8.encode('Công ty ABC gửi báo giá'));
        write('other.md', utf8.encode('Nothing relevant'));

        final all = await search('hop dong abc', useNative: useNative);
        expect(names(all.items), ['hop-dong.txt']);
        expect(all.items.single['matched_terms'], ['hop', 'dong', 'abc']);
        expect(all.items.single['snippets'], [
          {'line': 1, 'text': 'HỢP ĐỒNG thuê nhà'},
          {'line': 3, 'text': 'Bên B: Công ty ABC'},
        ]);
        expect(all.complete, true);
        expect(all.filesSearched, 3);

        final any = await search(
          'hop dong abc',
          useNative: useNative,
          matchAll: false,
        );
        expect(names(any.items), ['hop-dong.txt', 'abc-only.txt']);
        expect(any.items.last['missing_terms'], ['hop', 'dong']);

        final phrase = await search('"ty abc gui"', useNative: useNative);
        expect(names(phrase.items), ['abc-only.txt']);
      }, skip: skip);

      test('terms match where words start; code caches are skipped', () async {
        // The reported case: a note with "F95" ranked below Go unicode
        // tables whose hex ("0x1f95f") matched hundreds of times.
        write(
          'OneDrive/Sync/New Text Document.txt',
          utf8.encode('F95\nhttps://f95zone.to/forums/games.2/page-317'),
        );
        write('src/hex.go', utf8.encode('var t = 0x1f95f, 0xf950\n' * 200));
        write('go/pkg/mod/unicode/tables.go', utf8.encode('f95 ' * 500));
        write('.cargo/registry/readme.txt', utf8.encode('f95 ' * 500));

        final result = await search('f95', useNative: useNative);
        expect(names(result.items), ['New Text Document.txt']);
        expect(result.items.single['hits'], 2);
        final skipped = result.warnings.firstWhere(
          (w) => w.startsWith('Skipped system'),
        );
        expect(skipped, contains(p.join(sandbox.path, '.cargo')));
        expect(skipped, contains(p.join(sandbox.path, 'go', 'pkg', 'mod')));

        final number = await search('2048', useNative: useNative);
        expect(names(number.items), isEmpty);
        write('invoice.txt', utf8.encode('Ref INV2048'));
        final suffix = await search('2048', useNative: useNative);
        expect(names(suffix.items), ['invoice.txt']);
      }, skip: skip);

      test('Office, OpenDocument, EPUB and RTF text is searched', () async {
        documents().forEach(write);
        final result = await search('tien dien', useNative: useNative);
        expect(names(result.items).toSet(), {
          'invoice.docx',
          'budget.xlsx',
          'deck.pptx',
          'notes.odt',
          'book.epub',
          'letter.rtf',
          'plain.txt',
          'utf16.txt',
        });
        final deck = result.items.firstWhere((i) => i['name'] == 'deck.pptx');
        // slide2 is read before slide10.
        expect(deck['snippets'], [
          {'line': 2, 'text': 'Tiền điện'},
        ]);
      }, skip: skip);

      test('skipped files make the scope incomplete and say so', () async {
        write('scan.pdf', utf8.encode('%PDF-1.7 no text layer'));
        write('old.doc', utf8.encode('tien dien'));
        write('photo.jpg', [0xFF, 0xD8, 0xFF]);
        write('node_modules/pkg/readme.txt', utf8.encode('tien dien'));
        write('bill.txt', utf8.encode('tien dien'));
        write('AppData/Local/cache.txt', utf8.encode('tien dien'));
        // Binary despite its name: only the first 8 KiB are read.
        write('blob.txt', [0, ...utf8.encode('tien dien' * 2000)]);

        final result = await search('tien dien', useNative: useNative);
        expect(names(result.items), ['bill.txt']);
        expect(result.complete, false);
        expect(
          result.warnings.last,
          useNative
              ? 'Not searched, no text reader for these formats yet: 1 .doc.'
              : 'Not searched, no text reader for these formats yet: '
                    '1 .doc, 1 .pdf.',
        );
        expect(
          result.warnings,
          contains(
            'Skipped system and app-data folders '
            '(${p.join(sandbox.path, 'AppData')}); search inside one directly '
            'if it is needed.',
          ),
        );
        if (useNative) {
          expect(result.warnings.first, contains('1 document(s) have no text'));
        }
      }, skip: skip);
    });
  }

  test(
    'native and Dart searches return the same items for every format',
    () async {
      documents().forEach(write);
      for (final (query, matchAll) in [
        ('tien dien', true),
        ('dien nuoc ngan', false),
        ('"tiền điện"', true),
      ]) {
        List<dynamic> strip(ContentSearchOutcome outcome) => [
          for (final item in outcome.items) {...item}..remove('modified'),
        ];
        final native = await search(query, useNative: true, matchAll: matchAll);
        final dart = await search(query, useNative: false, matchAll: matchAll);
        expect(strip(native), strip(dart), reason: query);
        expect(native.filesSearched, dart.filesSearched, reason: query);
      }
    },
    skip: nativeSkip,
  );

  test(
    'native document text equals the Dart extractor for every format',
    () async {
      for (final MapEntry(key: name, value: bytes) in documents().entries) {
        final file = write(name, bytes);
        final format = DocumentText.formatOf(file.path);
        final native = await NativeContent.documentText(file.path, format);
        expect(
          native!.text,
          DocumentText.extract(format, Uint8List.fromList(bytes)),
          reason: name,
        );
      }
    },
    skip: nativeSkip,
  );

  test('PDF text is searched and read natively', () async {
    write('Hoa don.pdf', pdf('Hoa don tien dien thang 9'));
    final result = await run('search_content', {'query': 'tien dien'});
    final item = (result['items'] as List).single as Map<String, dynamic>;
    expect(item['format'], 'pdf');
    // pdf-extract starts a page with blank lines; read_file shows the same.
    expect(item['snippets'], [
      {'line': 3, 'text': 'Hoa don tien dien thang 9'},
    ]);
    final read = await run('read_file', {'path': 'Hoa don.pdf'});
    expect(read['format'], 'pdf');
    expect((read['lines'] as List)[2], {
      'line': 3,
      'text': 'Hoa don tien dien thang 9',
    });
  }, skip: nativeSkip);

  test('read_file reads documents at the lines search reports', () async {
    documents().forEach(write);
    final read = await run('read_file', {'path': 'invoice.docx'});
    expect(read['format'], 'docx');
    expect(read['lines'], [
      {'line': 1, 'text': 'Hóa đơn tiền điện'},
      {'line': 2, 'text': 'Tháng 9 & tháng 10'},
      {'line': 3, 'text': 'Trang 1'},
    ]);
  });

  test('UTF-16, RTF and invalid entities decode safely', () {
    final docs = documents();
    expect(
      DocumentText.extract('text', Uint8List.fromList(docs['utf16.txt']!)),
      'Biên bản tiền điện',
    );
    expect(
      DocumentText.extract('rtf', Uint8List.fromList(docs['letter.rtf']!)),
      'Tiền điện\na{b}c',
    );
    expect(
      DocumentText.xmlText('<p>a&#999999999;b&#xD800;c</p>'),
      'a${String.fromCharCode(0xFFFD)}b${String.fromCharCode(0xFFFD)}c',
    );
  });

  test('the fast search key equals TextUtils.searchKey', () {
    String c(int code) => String.fromCharCode(code);
    final samples = [
      '',
      '   ',
      'Hello World',
      '  HỢP ĐỒNG   thuê\tnhà  ',
      'Tiếng Việt: Đặng Thị Ánh (2024) [bản_sao]{v1.2}-final',
      'cha${c(0x300)}o ba${c(0x323)}n',
      'Café über Æsir straße İstanbul',
      'non${c(0xA0)}breaking${c(0x2003)}em${c(0x3000)}ideographic${c(0xFEFF)}bom',
      'ΑΘΗΝΑ Ελληνικά — дом ДОМ — 中文 日本語',
      'emoji 😀 mixed 𝔘𝔫𝔦𝔠𝔬𝔡𝔢',
      'a__b--c..d((e))[[f]]{{g}}',
    ];
    for (final sample in samples) {
      expect(
        ContentSearch.searchKey(sample),
        TextUtils.searchKey(sample),
        reason: sample,
      );
    }
  });

  test('stopping the turn stops a running content search', () async {
    for (var i = 0; i < 200; i++) {
      write('dir$i/file.txt', utf8.encode('needle'));
    }
    final running = executor.execute(
      const ToolCall(name: 'search_content', arguments: {'query': 'needle'}),
    );
    // The executor has passed its own pre-check; the search must notice.
    cancelled = true;
    final result = await running;
    expect(result.success, false);
    expect(result.output, contains('stopped by user'));
  });

  test('an empty cursor and null options mean "not given"', () async {
    write('bill.txt', utf8.encode('INV-2048'));
    // Seen from Qwen3.5-4B: the first call already carried these.
    final result = await run('search_content', {
      'query': 'INV-2048',
      'cursor': '',
      'extension': null,
      'limit': null,
    });
    expect(names(result['items'] as List), ['bill.txt']);
  });

  test('invalid match mode is rejected before running', () async {
    final result = await executor.execute(
      const ToolCall(
        name: 'search_content',
        arguments: {'query': 'x', 'match': 'some'},
      ),
    );
    expect(result.success, false);
    expect(result.output, contains('match must be'));
  });
}
