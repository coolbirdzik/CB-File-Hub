//! Searchable text of documents, for the agent's content search.
//!
//! Mirrors `DocumentText` in
//! cb_file_manager/lib/services/ai/document_text.dart step by step, so a
//! native and a Dart search report the same line numbers and `read_file`
//! pages the text a search matched. PDF is only read here.

use std::io::{Cursor, Read};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::OnceLock;

use regex::Regex;

use crate::normalize::dart_compare;

pub const MAX_PLAIN_TEXT_BYTES: u64 = 2 * 1024 * 1024;
pub const MAX_DOCUMENT_BYTES: u64 = 64 * 1024 * 1024;
/// In UTF-16 code units, like Dart's `String.length`.
pub const MAX_EXTRACTED_UNITS: usize = 4 * 1024 * 1024;
/// A zip entry inflating past this is not a real document part.
const MAX_ENTRY_BYTES: u64 = 64 * 1024 * 1024;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Format {
    Text,
    Rtf,
    Docx,
    Xlsx,
    Pptx,
    OpenDocument,
    Epub,
    Pdf,
    Unsupported,
    Binary,
}

const BINARY_EXTENSIONS: &[&str] = &[
    ".jpg",
    ".jpeg",
    ".png",
    ".gif",
    ".bmp",
    ".webp",
    ".heic",
    ".tif",
    ".tiff",
    ".ico",
    ".psd",
    ".raw",
    ".cr2",
    ".nef",
    ".mp4",
    ".mkv",
    ".avi",
    ".mov",
    ".wmv",
    ".webm",
    ".flv",
    ".m4v",
    ".mp3",
    ".wav",
    ".flac",
    ".aac",
    ".ogg",
    ".m4a",
    ".wma",
    ".zip",
    ".rar",
    ".7z",
    ".gz",
    ".tgz",
    ".bz2",
    ".xz",
    ".tar",
    ".iso",
    ".img",
    ".vhd",
    ".vhdx",
    ".exe",
    ".dll",
    ".sys",
    ".msi",
    ".bin",
    ".dat",
    ".db",
    ".sqlite",
    ".class",
    ".jar",
    ".so",
    ".dylib",
    ".o",
    ".obj",
    ".lib",
    ".pdb",
    ".woff",
    ".woff2",
    ".ttf",
    ".otf",
    ".gguf",
    ".safetensors",
    ".pt",
    ".onnx",
];

impl Format {
    /// From a lower-cased package:path extension (with its dot).
    pub fn of(extension: &str) -> Format {
        match extension {
            ".docx" | ".docm" | ".dotx" => Format::Docx,
            ".xlsx" | ".xlsm" => Format::Xlsx,
            ".pptx" | ".pptm" => Format::Pptx,
            ".odt" | ".ods" | ".odp" => Format::OpenDocument,
            ".epub" => Format::Epub,
            ".rtf" => Format::Rtf,
            ".pdf" => Format::Pdf,
            ".doc" | ".xls" | ".ppt" => Format::Unsupported,
            _ if BINARY_EXTENSIONS.contains(&extension) => Format::Binary,
            _ => Format::Text,
        }
    }

    /// The name Dart uses for the format.
    pub fn name(self) -> &'static str {
        match self {
            Format::Text => "text",
            Format::Rtf => "rtf",
            Format::Docx => "docx",
            Format::Xlsx => "xlsx",
            Format::Pptx => "pptx",
            Format::OpenDocument => "opendocument",
            Format::Epub => "epub",
            Format::Pdf => "pdf",
            Format::Unsupported => "unsupported",
            Format::Binary => "binary",
        }
    }

    pub fn from_name(name: &str) -> Option<Format> {
        [
            Format::Text,
            Format::Rtf,
            Format::Docx,
            Format::Xlsx,
            Format::Pptx,
            Format::OpenDocument,
            Format::Epub,
            Format::Pdf,
        ]
        .into_iter()
        .find(|format| format.name() == name)
    }

    pub fn max_bytes(self) -> u64 {
        if self == Format::Text {
            MAX_PLAIN_TEXT_BYTES
        } else {
            MAX_DOCUMENT_BYTES
        }
    }
}

fn regex(cell: &'static OnceLock<Regex>, pattern: &str) -> &'static Regex {
    cell.get_or_init(|| Regex::new(pattern).expect("valid pattern"))
}

macro_rules! pattern {
    ($name:ident, $pattern:expr) => {
        fn $name() -> &'static Regex {
            static CELL: OnceLock<Regex> = OnceLock::new();
            regex(&CELL, $pattern)
        }
    };
}

pattern!(
    docx_part,
    r"^word/(header|footer)[0-9]*\.xml$|^word/(footnotes|endnotes|comments)\.xml$"
);
pattern!(xlsx_sheet, r"^xl/worksheets/sheet[0-9]+\.xml$");
pattern!(
    pptx_part,
    r"^ppt/(slides/slide|notesSlides/notesSlide)[0-9]+\.xml$"
);
pattern!(epub_part, r"(?i)\.(x?html?)$");
pattern!(inline_string, r"<is>([\s\S]*?)</is>");
pattern!(script_block, r"<script(?-u:\b)[\s\S]*?</script>");
pattern!(style_block, r"<style(?-u:\b)[\s\S]*?</style>");
pattern!(
    block_end,
    r"</(?:w:p|a:p|text:p|text:h|p|h[1-6]|li|div|tr|si|title)>|<(?:w:br|w:cr|a:br|text:line-break|br)(?-u:\b)[^>]*>"
);
pattern!(
    cell_break,
    r"<(?:w:tab|text:tab)(?-u:\b)[^>]*>|</(?:td|th|table:table-cell|w:tc)>"
);
pattern!(tag, r"<[^>]*>");
pattern!(entity, r"&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);");
pattern!(line_gap, r"[ \t]*\n[ \t\n]*");
pattern!(
    rtf_destination,
    r"\{\\(?:\*|fonttbl|colortbl|stylesheet|info|pict)[^{}]*(?:\{[^{}]*\}[^{}]*)*\}"
);
pattern!(rtf_unicode, r"\\u(-?[0-9]+)\??");
pattern!(rtf_hex, r"\\'([0-9a-fA-F]{2})");
pattern!(rtf_break, r"\\(?:par|line|row)(?-u:\b) ?");
pattern!(rtf_tab, r"\\(?:tab|cell)(?-u:\b) ?");
pattern!(rtf_word, r"\\[a-zA-Z]+-?[0-9]* ?");
pattern!(blank_lines, r"\n{3,}");

/// Dart's `String.trim`.
fn dart_trim(value: &str) -> &str {
    let bom = char::from_u32(0xFEFF).unwrap_or(' ');
    value.trim_matches(|c: char| c.is_whitespace() || c == bom)
}

/// A code point, or U+FFFD where Dart would build an invalid string.
fn code_point(value: i64) -> char {
    u32::try_from(value)
        .ok()
        .and_then(char::from_u32)
        .unwrap_or(char::REPLACEMENT_CHARACTER)
}

/// Text of a file in `format`, or None when it is binary or unreadable.
pub fn extract(format: Format, bytes: &[u8]) -> Option<String> {
    let text = match format {
        Format::Text => plain_text(bytes),
        Format::Rtf => Some(rtf_text(&plain_text(bytes).unwrap_or_default())),
        Format::Docx => zip_text(
            bytes,
            |name| name == "word/document.xml" || docx_part().is_match(name),
            false,
        ),
        Format::Xlsx => zip_text(
            bytes,
            |name| name == "xl/sharedStrings.xml" || xlsx_sheet().is_match(name),
            true,
        ),
        Format::Pptx => zip_text(bytes, |name| pptx_part().is_match(name), false),
        Format::OpenDocument => zip_text(bytes, |name| name == "content.xml", false),
        Format::Epub => zip_text(bytes, |name| epub_part().is_match(name), false),
        Format::Pdf => pdf_text(bytes),
        Format::Unsupported | Format::Binary => None,
    }?;
    Some(truncate_units(text, MAX_EXTRACTED_UNITS))
}

fn truncate_units(text: String, max: usize) -> String {
    let mut units = 0;
    for (index, c) in text.char_indices() {
        units += c.len_utf16();
        if units > max {
            let mut text = text;
            text.truncate(index);
            return text;
        }
    }
    text
}

fn plain_text(bytes: &[u8]) -> Option<String> {
    if bytes.len() >= 2 {
        if bytes[0] == 0xFF && bytes[1] == 0xFE {
            return Some(utf16(&bytes[2..], true));
        }
        if bytes[0] == 0xFE && bytes[1] == 0xFF {
            return Some(utf16(&bytes[2..], false));
        }
    }
    if bytes[..bytes.len().min(8192)].contains(&0) {
        return None;
    }
    let start = if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        3
    } else {
        0
    };
    Some(String::from_utf8_lossy(&bytes[start..]).into_owned())
}

fn utf16(bytes: &[u8], little_endian: bool) -> String {
    let units: Vec<u16> = bytes
        .chunks_exact(2)
        .map(|pair| {
            if little_endian {
                u16::from_le_bytes([pair[0], pair[1]])
            } else {
                u16::from_be_bytes([pair[0], pair[1]])
            }
        })
        .collect();
    String::from_utf16_lossy(&units)
}

/// `_naturalCompare`: slide2 before slide10.
fn natural_key(name: &str) -> String {
    let mut key = String::with_capacity(name.len() + 8);
    let mut digits = String::new();
    let flush = |digits: &mut String, key: &mut String| {
        if !digits.is_empty() {
            for _ in digits.len()..8 {
                key.push('0');
            }
            key.push_str(digits);
            digits.clear();
        }
    };
    for c in name.chars() {
        if c.is_ascii_digit() {
            digits.push(c);
        } else {
            flush(&mut digits, &mut key);
            key.push(c);
        }
    }
    flush(&mut digits, &mut key);
    key
}

fn zip_text(
    bytes: &[u8],
    wanted: impl Fn(&str) -> bool,
    sheet_inline_only: bool,
) -> Option<String> {
    let mut archive = zip::ZipArchive::new(Cursor::new(bytes)).ok()?;
    let mut names: Vec<String> = archive
        .file_names()
        .filter_map(|name| name.ok().map(|name| name.into_owned()))
        .filter(|name| !name.ends_with('/') && wanted(name))
        .collect();
    names.sort_by(|a, b| dart_compare(&natural_key(a), &natural_key(b)));

    let mut parts: Vec<String> = Vec::new();
    let mut length = 0;
    let add = |text: String, parts: &mut Vec<String>, length: &mut usize| {
        if !text.is_empty() {
            *length += text.encode_utf16().count() + 1;
            parts.push(text);
        }
    };
    for name in names {
        let mut raw = Vec::new();
        archive
            .by_name(&name)
            .ok()?
            .take(MAX_ENTRY_BYTES)
            .read_to_end(&mut raw)
            .ok()?;
        let xml = String::from_utf8_lossy(&raw);
        if sheet_inline_only && name.starts_with("xl/worksheets/") {
            // Shared strings hold most cell text; sheets add inline strings.
            for cell in inline_string().captures_iter(&xml) {
                add(xml_text(&cell[1]), &mut parts, &mut length);
            }
        } else {
            add(xml_text(&xml), &mut parts, &mut length);
        }
        if length > MAX_EXTRACTED_UNITS {
            break;
        }
    }
    Some(parts.join("\n"))
}

/// `DocumentText.xmlText`: visible text, one paragraph per line.
pub fn xml_text(xml: &str) -> String {
    let text = script_block().replace_all(xml, "");
    let text = style_block().replace_all(&text, "");
    let text = block_end().replace_all(&text, "\n");
    let text = cell_break().replace_all(&text, "\t");
    let text = tag().replace_all(&text, "");
    let text = entity().replace_all(&text, |caps: &regex::Captures| {
        let value = &caps[1];
        match value {
            "amp" => "&".to_string(),
            "lt" => "<".to_string(),
            "gt" => ">".to_string(),
            "quot" => "\"".to_string(),
            "apos" => "'".to_string(),
            _ => {
                let parsed = if let Some(hex) = value.strip_prefix("#x") {
                    i64::from_str_radix(hex, 16).ok()
                } else {
                    value[1..].parse::<i64>().ok()
                };
                code_point(parsed.unwrap_or(-1)).to_string()
            }
        }
    });
    let text = line_gap().replace_all(&text, "\n");
    dart_trim(&text).to_string()
}

fn rtf_text(rtf: &str) -> String {
    let text = rtf_destination().replace_all(rtf, "");
    let text = rtf_unicode().replace_all(&text, |caps: &regex::Captures| {
        code_point(caps[1].parse::<i64>().unwrap_or(-1) & 0xFFFF).to_string()
    });
    let text = rtf_hex().replace_all(&text, |caps: &regex::Captures| {
        code_point(i64::from_str_radix(&caps[1], 16).unwrap_or(-1)).to_string()
    });
    let text = rtf_break().replace_all(&text, "\n");
    let text = rtf_tab().replace_all(&text, "\t");
    let text = rtf_word().replace_all(&text, "");

    // Braces not escaped by a backslash are groups, not text.
    let chars: Vec<char> = text.chars().collect();
    let mut unbraced = Vec::with_capacity(chars.len());
    for (index, &c) in chars.iter().enumerate() {
        if (c == '{' || c == '}') && (index == 0 || chars[index - 1] != '\\') {
            continue;
        }
        unbraced.push(c);
    }
    // Then `\\`, `\{` and `\}` become the character they escape.
    let mut text = String::with_capacity(unbraced.len());
    let mut index = 0;
    while index < unbraced.len() {
        let c = unbraced[index];
        if c == '\\' && matches!(unbraced.get(index + 1), Some('\\' | '{' | '}')) {
            text.push(unbraced[index + 1]);
            index += 2;
            continue;
        }
        text.push(c);
        index += 1;
    }
    let text = blank_lines().replace_all(&text, "\n\n");
    dart_trim(&text).to_string()
}

/// PDF text through pdf-extract; a malformed file is skipped, never fatal.
fn pdf_text(bytes: &[u8]) -> Option<String> {
    quiet_pdf_panics();
    catch_unwind(AssertUnwindSafe(|| {
        pdf_extract::extract_text_from_mem(bytes)
    }))
    .ok()?
    .ok()
}

/// pdf-extract panics on PDFs it cannot parse (Type3 fonts without widths,
/// empty arrays). [`pdf_text`] catches those, but the default hook still
/// prints each one like a crash. Installed once; panics from anywhere else
/// still reach the previous hook.
fn quiet_pdf_panics() {
    static INSTALLED: OnceLock<()> = OnceLock::new();
    INSTALLED.get_or_init(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            let from_pdf = info
                .location()
                .is_some_and(|location| location.file().contains("pdf-extract"));
            if !from_pdf {
                previous(info);
            }
        }));
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn zip(entries: &[(&str, &str)]) -> Vec<u8> {
        let mut out = zip::ZipWriter::new(Cursor::new(Vec::new()));
        for (name, content) in entries {
            out.start_file(*name, zip::write::SimpleFileOptions::default())
                .unwrap();
            out.write_all(content.as_bytes()).unwrap();
        }
        out.finish().unwrap().into_inner()
    }

    #[test]
    fn reads_office_parts_in_natural_order() {
        let docx = zip(&[
            (
                "word/document.xml",
                "<w:p><w:r><w:t>Hóa đơn</w:t></w:r></w:p><w:p><w:t>A &amp; B&#x1F600;&#99999999;</w:t></w:p>",
            ),
            ("word/styles.xml", "<w:t>ignored</w:t>"),
        ]);
        let text = extract(Format::Docx, &docx).unwrap();
        assert_eq!(text, "Hóa đơn\nA & B😀\u{FFFD}");

        let pptx = zip(&[
            ("ppt/slides/slide10.xml", "<a:p><a:t>ten</a:t></a:p>"),
            ("ppt/slides/slide2.xml", "<a:p><a:t>two</a:t></a:p>"),
        ]);
        assert_eq!(extract(Format::Pptx, &pptx).unwrap(), "two\nten");

        let xlsx = zip(&[
            ("xl/sharedStrings.xml", "<sst><si><t>Shared</t></si></sst>"),
            (
                "xl/worksheets/sheet1.xml",
                "<c><v>3</v></c><c t=\"inlineStr\"><is><t>Inline</t></is></c>",
            ),
        ]);
        assert_eq!(extract(Format::Xlsx, &xlsx).unwrap(), "Shared\nInline");
    }

    #[test]
    fn decodes_plain_text_and_rtf() {
        assert_eq!(extract(Format::Text, &[0, 1, 2]), None);
        let mut utf16 = vec![0xFF, 0xFE];
        for unit in "Biên".encode_utf16() {
            utf16.extend_from_slice(&unit.to_le_bytes());
        }
        assert_eq!(extract(Format::Text, &utf16).unwrap(), "Biên");
        let rtf = br"{\rtf1{\fonttbl{\f0 Arial;}}\f0 Bi\u234?n b\u7843?n\par a\{b\}c}";
        assert_eq!(extract(Format::Rtf, rtf).unwrap(), "Biên bản\na{b}c");
    }

    #[test]
    fn malformed_documents_are_skipped() {
        assert_eq!(extract(Format::Docx, b"not a zip"), None);
        assert_eq!(extract(Format::Pdf, b"%PDF-1.7 garbage"), None);
    }
}
