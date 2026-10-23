//! Bounded bencode/metainfo parser. Identity always hashes the original info
//! slice, including noncanonical dictionary ordering. No payload data is read.
use crate::{job::Job, normalize::dart_lower, wire::Writer};
use sha1::{Digest, Sha1};
use std::{
    collections::{BTreeMap, HashSet},
    sync::Arc,
};

enum Value<'a> {
    Int(i64),
    Bytes(&'a [u8]),
    List(Vec<Value<'a>>),
    Map(BTreeMap<String, Value<'a>>),
}
impl<'a> Value<'a> {
    fn int(&self) -> Option<i64> {
        if let Self::Int(v) = self {
            Some(*v)
        } else {
            None
        }
    }
    fn bytes(&self) -> Option<&'a [u8]> {
        if let Self::Bytes(v) = self {
            Some(v)
        } else {
            None
        }
    }
    fn map(&self) -> Option<&BTreeMap<String, Value<'a>>> {
        if let Self::Map(v) = self {
            Some(v)
        } else {
            None
        }
    }
    fn list(&self) -> Option<&Vec<Value<'a>>> {
        if let Self::List(v) = self {
            Some(v)
        } else {
            None
        }
    }
}
type Result<T> = std::result::Result<T, String>;
fn bad() -> String {
    "invalid torrent metainfo".into()
}
fn text(v: &Value<'_>) -> Result<String> {
    // Dart allows malformed UTF-8. Let its fallback handle that uncommon case
    // rather than changing replacement-character or path-validation semantics.
    Ok(std::str::from_utf8(v.bytes().ok_or_else(bad)?)
        .map_err(|_| bad())?
        .to_string())
}
struct Parser<'a> {
    bytes: &'a [u8],
    at: usize,
    info: Option<(usize, usize)>,
}
impl<'a> Parser<'a> {
    fn read(&mut self, depth: u8) -> Result<Value<'a>> {
        if depth > 64 {
            return Err(bad());
        }
        let kind = *self.bytes.get(self.at).ok_or_else(bad)?;
        self.at += 1;
        match kind {
            b'i' => {
                let start = self.at;
                while self.bytes.get(self.at).is_some_and(|v| *v != b'e') {
                    self.at += 1;
                }
                if self.at == self.bytes.len() {
                    return Err(bad());
                }
                let raw = std::str::from_utf8(&self.bytes[start..self.at]).map_err(|_| bad())?;
                self.at += 1;
                let digits = raw.strip_prefix('-').unwrap_or(raw);
                if digits.is_empty()
                    || !digits.bytes().all(|b| b.is_ascii_digit())
                    || (digits.starts_with('0') && raw != "0")
                {
                    return Err(bad());
                }
                Ok(Value::Int(raw.parse().map_err(|_| bad())?))
            }
            b'l' | b'd' => {
                let mut list = Vec::new();
                let mut map = BTreeMap::new();
                while self.bytes.get(self.at).is_some_and(|v| *v != b'e') {
                    if kind == b'l' {
                        list.push(self.read(depth + 1)?);
                    } else {
                        let key = text(&self.read(depth + 1)?)?;
                        if map.contains_key(&key) {
                            return Err(bad());
                        }
                        let start = self.at;
                        let value = self.read(depth + 1)?;
                        if depth == 0 && key == "info" {
                            self.info = Some((start, self.at));
                        }
                        map.insert(key, value);
                    }
                }
                if self.bytes.get(self.at) != Some(&b'e') {
                    return Err(bad());
                }
                self.at += 1;
                Ok(if kind == b'l' {
                    Value::List(list)
                } else {
                    Value::Map(map)
                })
            }
            b'0'..=b'9' => {
                let start = self.at - 1;
                while self.bytes.get(self.at).is_some_and(|v| v.is_ascii_digit()) {
                    self.at += 1;
                }
                if self.bytes.get(self.at) != Some(&b':') {
                    return Err(bad());
                }
                let len: usize = std::str::from_utf8(&self.bytes[start..self.at])
                    .map_err(|_| bad())?
                    .parse()
                    .map_err(|_| bad())?;
                self.at += 1;
                let end = self.at.checked_add(len).ok_or_else(bad)?;
                let bytes = self.bytes.get(self.at..end).ok_or_else(bad)?;
                self.at = end;
                Ok(Value::Bytes(bytes))
            }
            _ => Err(bad()),
        }
    }
}
fn safe(s: &str) -> Result<()> {
    let upper = s.split('.').next().unwrap_or("").to_ascii_uppercase();
    let reserved = matches!(upper.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || (upper.len() == 4
            && (upper.starts_with("COM") || upper.starts_with("LPT"))
            && matches!(upper.as_bytes()[3], b'1'..=b'9'));
    if s.is_empty()
        || s == "."
        || s == ".."
        || reserved
        || s.ends_with(['.', ' '])
        || s.chars()
            .any(|c| c <= '\u{1f}' || "/\\:*?\"<>|".contains(c))
    {
        return Err(bad());
    }
    Ok(())
}
fn whitespace(c: char) -> bool {
    matches!(c, '\t'..='\r' | ' ' | '\u{a0}' | '\u{1680}' | '\u{2000}'..='\u{200a}' | '\u{2028}' | '\u{2029}' | '\u{202f}' | '\u{205f}' | '\u{3000}' | '\u{feff}')
}
fn optional(value: Option<&Value<'_>>, limit: usize) -> Result<Option<String>> {
    let Some(bytes) = value.and_then(Value::bytes) else {
        return Ok(None);
    };
    let bytes = &bytes[..bytes.len().min(limit * 4)];
    let s = std::str::from_utf8(bytes)
        .map_err(|_| bad())?
        .trim_matches(whitespace);
    let units: Vec<u16> = s.encode_utf16().take(limit).collect();
    Ok(Some(String::from_utf16(&units).map_err(|_| bad())?))
}
fn optional_out(w: &mut Writer, value: Option<String>) {
    w.u8(u8::from(value.is_some()));
    if let Some(s) = value {
        w.str(&s);
    }
}

fn parse(bytes: &[u8]) -> Result<Vec<u8>> {
    if bytes.len() > 16 * 1024 * 1024 {
        return Err(bad());
    }
    let mut parser = Parser {
        bytes,
        at: 0,
        info: None,
    };
    let value = parser.read(0)?;
    if parser.at != bytes.len() {
        return Err(bad());
    }
    let root = value.map().ok_or_else(bad)?;
    let info = root.get("info").and_then(Value::map).ok_or_else(bad)?;
    let pieces = info.get("pieces").and_then(Value::bytes).ok_or_else(bad)?;
    let piece_length = info
        .get("piece length")
        .and_then(Value::int)
        .filter(|n| *n > 0)
        .ok_or_else(bad)?;
    let name = text(
        info.get("name.utf-8")
            .or_else(|| info.get("name"))
            .ok_or_else(bad)?,
    )?;
    safe(&name)?;
    if let Some(v) = info.get("name") {
        safe(&text(v)?)?;
    }
    let mut names = Vec::new();
    let mut total = 0i64;
    if let Some(files) = info.get("files") {
        let files = files.list().filter(|v| !v.is_empty()).ok_or_else(bad)?;
        let mut paths = HashSet::new();
        for file in files {
            let file = file.map().ok_or_else(bad)?;
            let parts = file
                .get("path.utf-8")
                .or_else(|| file.get("path"))
                .and_then(Value::list)
                .filter(|p| !p.is_empty())
                .ok_or_else(bad)?;
            let parts: Vec<String> = parts.iter().map(text).collect::<Result<_>>()?;
            for part in &parts {
                safe(part)?;
            }
            if !paths.insert(dart_lower(&parts.join("/"))) {
                return Err(bad());
            }
            if let Some(parts) = file.get("path").and_then(Value::list) {
                for part in parts {
                    safe(&text(part)?)?;
                }
            }
            names.push(dart_lower(parts.last().unwrap()));
            let length = file
                .get("length")
                .and_then(Value::int)
                .filter(|n| *n >= 0)
                .ok_or_else(bad)?;
            total = total.checked_add(length).ok_or_else(bad)?;
        }
    } else {
        total = info
            .get("length")
            .and_then(Value::int)
            .filter(|n| *n >= 0)
            .ok_or_else(bad)?;
        names.push(dart_lower(&name));
    }
    let expected = if total == 0 {
        0
    } else {
        1 + (total - 1) / piece_length
    };
    if expected.checked_mul(20) != Some(pieces.len() as i64) {
        return Err(bad());
    }
    let (start, end) = parser.info.ok_or_else(bad)?;
    let hash = format!("{:x}", Sha1::digest(&bytes[start..end]));
    let all_extensions = |exts: &[&str]| {
        names
            .iter()
            .all(|n| exts.iter().any(|ext| n.ends_with(ext)))
    };
    let category = if all_extensions(&[".mkv", ".mp4", ".avi", ".mov", ".webm", ".wmv"]) {
        "video"
    } else if all_extensions(&[".mp3", ".flac", ".wav", ".m4a", ".ogg", ".aac"]) {
        "audio"
    } else if all_extensions(&[".pdf", ".epub", ".txt", ".doc", ".docx"]) {
        "documents"
    } else {
        "other"
    };
    let mut trackers = Vec::new();
    let mut seen = HashSet::new();
    let mut add = |v| -> Result<()> {
        if let Some(s) = optional(v, 2048)? {
            if !s.is_empty() && trackers.len() < 128 && seen.insert(s.clone()) {
                trackers.push(s);
            }
        }
        Ok(())
    };
    if let Some(tiers) = root.get("announce-list").and_then(Value::list) {
        for tier in tiers {
            if let Some(tier) = tier.list() {
                for v in tier {
                    add(Some(v))?;
                }
            }
        }
    }
    add(root.get("announce"))?;
    let mut w = Writer::default();
    w.str(&hash);
    w.str(&name);
    w.i64(total);
    w.u32(names.len() as u32);
    w.str(category);
    w.u32(trackers.len() as u32);
    for tracker in trackers {
        w.str(&tracker);
    }
    optional_out(
        &mut w,
        optional(
            root.get("comment.utf-8").or_else(|| root.get("comment")),
            4096,
        )?,
    );
    optional_out(&mut w, optional(root.get("created by"), 4096)?);
    let date = root
        .get("creation date")
        .and_then(Value::int)
        .filter(|n| *n >= 0 && *n <= 8_640_000_000_000);
    w.u8(u8::from(date.is_some()));
    if let Some(date) = date {
        w.i64(date * 1000);
    }
    w.u8(u8::from(
        info.get("private").and_then(Value::int) == Some(1),
    ));
    w.i64(piece_length);
    w.i64(pieces.len() as i64 / 20);
    Ok(w.into_bytes())
}
pub fn start(port: i64, config: Vec<u8>) -> Option<Arc<Job>> {
    Some(Job::spawn(port, "cb_torrent_metainfo", move |job| {
        if job.cancelled() {
            return Ok(());
        }
        job.append(&parse(&config)?);
        Ok(())
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validates_paths_and_bencode() {
        for s in ["../x", "CON.txt", "NUL", "bad/part", "COM1", "x."] {
            assert!(safe(s).is_err());
        }
        assert!(safe("Tên ảnh.mp4").is_ok());
        for bytes in [b"i-0e".as_slice(), b"i01e", b"d1:ai1e1:ai2ee", b"3:ab"] {
            assert!(Parser {
                bytes,
                at: 0,
                info: None
            }
            .read(0)
            .is_err());
        }
    }
}
