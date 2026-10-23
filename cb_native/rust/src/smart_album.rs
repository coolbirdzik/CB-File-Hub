//! Stream media paths matching OR-ed album rules through the shared walk pool.
use crate::{
    fsx,
    normalize::dart_lower,
    walk::{self, Kind, Task, Walk, WalkStart},
    wire::{Reader, Writer},
};
use std::{collections::HashSet, fs};

enum Rule {
    Contains(String),
    Starts(String),
    Ends(String),
    Equals(String),
}
struct MediaWalk {
    extensions: HashSet<String>,
    rules: Vec<Rule>,
}
impl Kind for MediaWalk {
    fn scan(&self, walk: &Walk, task: &Task) -> Vec<Task> {
        let mut children = Vec::new();
        let mut out = Writer::default();
        let Ok(entries) = fs::read_dir(&task.path) else {
            return children;
        };
        walk.job.add_counter(2, 1);
        for entry in entries.flatten() {
            if walk.halted() {
                break;
            }
            let Ok(kind) = entry.file_type() else {
                continue;
            };
            if kind.is_symlink() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            let path = fsx::join(&task.path, &name);
            if kind.is_dir() {
                children.push(Task::dir(path, task.depth + 1));
                continue;
            }
            if !kind.is_file() {
                continue;
            }
            walk.job.add_counter(1, 1);
            if !self
                .extensions
                .contains(&dart_lower(fsx::last_dot_extension(&name)))
            {
                continue;
            }
            let ext = fsx::path_extension(&name);
            let base = dart_lower(&name[..name.len() - ext.len()]);
            let matches = self.rules.is_empty()
                || self.rules.iter().any(|rule| match rule {
                    Rule::Contains(s) => base.contains(s),
                    Rule::Starts(s) => base.starts_with(s),
                    Rule::Ends(s) => base.ends_with(s),
                    Rule::Equals(s) => base == *s,
                });
            if matches {
                out.str(&path);
                walk.job.add_counter(0, 1);
            }
        }
        walk.job.append(&out.into_bytes());
        children
    }
}
pub fn start(port: i64, config: &[u8]) -> WalkStart {
    let mut r = Reader::new(config);
    let decoded = (|| {
        let roots = r.strs()?;
        let extensions = r.strs()?;
        let count = r.u32()?;
        let mut rules = Vec::new();
        for _ in 0..count {
            rules.push((r.u8()?, r.str()?));
        }
        Some((roots, extensions, rules))
    })();
    let Some((roots, extensions, raw_rules)) = decoded else {
        return WalkStart::InvalidConfig;
    };
    if !r.is_empty() {
        return WalkStart::InvalidConfig;
    }
    let mut rules = Vec::new();
    for (kind, pattern) in raw_rules {
        let lower = dart_lower(&pattern);
        rules.push(match kind {
            0 => Rule::Contains(lower),
            1 => Rule::Starts(lower),
            2 => Rule::Ends(lower),
            3 => Rule::Equals(lower),
            // Dart RegExp has ECMAScript character classes and case folding.
            // Rust regex differs even for some supported expressions.
            4 => return WalkStart::InvalidRegex,
            _ => return WalkStart::InvalidConfig,
        });
    }
    WalkStart::Started(walk::start(
        port,
        roots.into_iter().map(|p| Task::dir(p, 0)).collect(),
        Box::new(MediaWalk {
            extensions: extensions.into_iter().collect(),
            rules,
        }),
    ))
}
