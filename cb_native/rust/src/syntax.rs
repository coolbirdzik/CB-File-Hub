//! Syntax scopes converted to theme-independent UTF-16 token ranges.
use crate::{
    job::Job,
    wire::{Reader, Writer},
};
use std::sync::{Arc, OnceLock};
use syntect::{
    easy::ScopeRegionIterator,
    parsing::{ParseState, ScopeStack, SyntaxSet},
    util::LinesWithEndings,
};

static SYNTAXES: OnceLock<SyntaxSet> = OnceLock::new();

fn class(stack: &ScopeStack) -> &'static str {
    for scope in stack.as_slice().iter().rev() {
        let s = scope.build_string();
        if s.starts_with("comment") {
            return "comment";
        }
        if s.starts_with("string") {
            return "string";
        }
        if s.starts_with("constant.numeric") {
            return "number";
        }
        if s.starts_with("constant.language") {
            return "literal";
        }
        if s.starts_with("keyword") || s.starts_with("storage") {
            return "keyword";
        }
        if s.starts_with("entity.name.function") {
            return "title";
        }
        if s.starts_with("entity.name.type") || s.starts_with("support.type") {
            return "type";
        }
        if s.starts_with("support.function") {
            return "built_in";
        }
        if s.starts_with("entity.name.tag") {
            return "name";
        }
        if s.starts_with("entity.other.attribute") {
            return "attr";
        }
    }
    ""
}

pub fn start(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let language = r.str()?;
    let source = r.str()?;
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_syntax", move |job| {
        let syntaxes = SYNTAXES.get_or_init(SyntaxSet::load_defaults_newlines);
        let extension = match language.as_str() {
            "javascript" => "js",
            "typescript" => "ts",
            "python" => "py",
            "csharp" => "cs",
            "ruby" => "rb",
            "markdown" => "md",
            "bash" => "sh",
            "powershell" => "ps1",
            "dos" => "bat",
            "protobuf" => "proto",
            "perl" => "pl",
            "rust" => "rs",
            "kotlin" => "kt",
            "scala" => "scala",
            "ini" => "ini",
            s => s,
        };
        let syntax = syntaxes
            .find_syntax_by_extension(extension)
            .ok_or("unsupported syntax")?;
        let mut parser = ParseState::new(syntax);
        let mut stack = ScopeStack::new();
        let mut offset = 0u32;
        let mut spans: Vec<(u32, u32, &str)> = Vec::new();
        for line in LinesWithEndings::from(&source) {
            if job.cancelled() {
                return Ok(());
            }
            let ops = parser
                .parse_line(line, syntaxes)
                .map_err(|e| e.to_string())?;
            for (text, op) in ScopeRegionIterator::new(&ops, line) {
                stack.apply(op).map_err(|e| e.to_string())?;
                let len = text.encode_utf16().count() as u32;
                if len == 0 {
                    continue;
                }
                let class = class(&stack);
                if let Some(last) = spans.last_mut().filter(|s| s.2 == class) {
                    last.1 += len;
                } else {
                    spans.push((offset, len, class));
                }
                offset += len;
            }
        }
        let mut out = Writer::default();
        for (start, len, class) in spans {
            out.u32(start);
            out.u32(len);
            out.str(class);
        }
        job.append(&out.into_bytes());
        Ok(())
    }))
}
