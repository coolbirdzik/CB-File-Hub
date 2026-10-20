//! Port of `TextUtils.searchKey` (cb_file_manager/lib/helpers/core/text_utils.dart).
//!
//! The steps and their order mirror the Dart code exactly, because a file must
//! match the same queries whether the native or the Dart search found it:
//! lowercase -> `removeDiacritics` -> strip combining marks -> separators to
//! spaces -> collapse whitespace -> trim.

use crate::fold_table::{FOLD_TABLE, LOWER_TABLE, UPPER_TABLE};

fn case_mapping(table: &'static [(u32, &'static str)], c: char) -> Option<&'static str> {
    table
        .binary_search_by_key(&(c as u32), |&(key, _)| key)
        .ok()
        .map(|index| table[index].1)
}

/// Dart's `toLowerCase` for one code point (generated from the Dart SDK).
fn push_lowercase(c: char, out: &mut String) {
    match case_mapping(LOWER_TABLE, c) {
        Some(mapped) => out.push_str(mapped),
        None => out.push(c),
    }
}

/// Dart's `String.toLowerCase` (generated from the Dart SDK).
pub fn dart_lower(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        push_lowercase(c, &mut out);
    }
    out
}

/// Dart's `String.compareTo`: lexicographic over UTF-16 code units.
pub fn dart_compare(a: &str, b: &str) -> std::cmp::Ordering {
    a.encode_utf16().cmp(b.encode_utf16())
}

/// Dart's `String.toUpperCase` (generated from the Dart SDK).
pub fn dart_upper(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        match case_mapping(UPPER_TABLE, c) {
            Some(mapped) => out.push_str(mapped),
            None => out.push(c),
        }
    }
    out
}

fn fold_unit(unit: u16) -> Option<&'static [u16]> {
    FOLD_TABLE
        .binary_search_by_key(&unit, |&(key, _)| key)
        .ok()
        .map(|index| FOLD_TABLE[index].1)
}

/// `_combiningDiacritics` in text_utils.dart.
fn is_combining_mark(c: char) -> bool {
    matches!(
        c as u32,
        0x0300..=0x036F | 0x1AB0..=0x1AFF | 0x1DC0..=0x1DFF | 0x20D0..=0x20FF | 0xFE20..=0xFE2F
    )
}

/// `[_\-\.\(\)\[\]\{\}]` in `_cleanString`.
fn is_separator(c: char) -> bool {
    matches!(c, '_' | '-' | '.' | '(' | ')' | '[' | ']' | '{' | '}')
}

/// Dart's RegExp `\s` (ECMAScript WhiteSpace + LineTerminator).
fn is_regexp_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n' | '\u{0B}' | '\u{0C}' | '\r' | ' ' | '\u{A0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200A}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202F}'
                | '\u{205F}'
                | '\u{3000}'
                | '\u{FEFF}'
    )
}

/// Dart's `String.trim` whitespace: Unicode White_Space plus BOM.
fn is_trim_space(c: char) -> bool {
    c.is_whitespace() || c == '\u{FEFF}'
}

/// Same result as `TextUtils.searchKey(value)`.
pub fn search_key(value: &str) -> String {
    let lower = dart_lower(value);

    let mut units: Vec<u16> = Vec::with_capacity(lower.len());
    for unit in lower.encode_utf16() {
        match fold_unit(unit) {
            Some(replacement) => units.extend_from_slice(replacement),
            None => units.push(unit),
        }
    }
    let folded = String::from_utf16_lossy(&units);

    let mut collapsed = String::with_capacity(folded.len());
    let mut pending_space = false;
    for c in folded.chars() {
        if is_combining_mark(c) {
            continue;
        }
        let c = if is_separator(c) { ' ' } else { c };
        if is_regexp_space(c) {
            pending_space = true;
            continue;
        }
        if pending_space {
            collapsed.push(' ');
            pending_space = false;
        }
        collapsed.push(c);
    }
    if pending_space {
        collapsed.push(' ');
    }
    collapsed.trim_matches(is_trim_space).to_string()
}

#[cfg(test)]
mod tests {
    use super::{dart_compare, search_key};
    use std::cmp::Ordering;

    #[test]
    fn compares_like_dart_utf16() {
        // U+FF61 sorts before U+1F600 by code point but after it in UTF-16.
        assert_eq!(dart_compare("\u{FF61}", "\u{1F600}"), Ordering::Greater);
        assert_eq!(dart_compare("a", "b"), Ordering::Less);
        assert_eq!(dart_compare("ab", "a"), Ordering::Greater);
    }

    #[test]
    fn folds_vietnamese_and_separators() {
        assert_eq!(search_key("Bổ Não_(final).MP4"), "bo nao final mp4");
        assert_eq!(search_key("cha\u{300}o"), "chao");
        assert_eq!(search_key("Đường  đi"), "duong di");
        assert_eq!(search_key("  über-café  "), "uber cafe");
    }
}
