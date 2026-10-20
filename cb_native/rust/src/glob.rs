//! The `*` / `?` file globs of the Disk Cleaner junk rules.
//!
//! Dart turns each glob into `^glob$` with `*` -> `.*` and `?` -> `.` and
//! matches it case-insensitively. Callers upper-case both sides with
//! `dart_upper` first, so this only has to match literally.

/// Dart's `.` skips line terminators.
fn wildcard_char(c: char) -> bool {
    !matches!(c, '\n' | '\r' | '\u{2028}' | '\u{2029}')
}

pub fn glob_matches(glob: &[char], name: &[char]) -> bool {
    let (mut g, mut n) = (0, 0);
    let mut star: Option<(usize, usize)> = None;
    while n < name.len() {
        if g < glob.len() && glob[g] == '*' {
            star = Some((g, n));
            g += 1;
        } else if g < glob.len()
            && ((glob[g] == '?' && wildcard_char(name[n])) || glob[g] == name[n])
        {
            g += 1;
            n += 1;
        } else if let Some((star_g, star_n)) = star {
            if !wildcard_char(name[star_n]) {
                return false;
            }
            g = star_g + 1;
            n = star_n + 1;
            star = Some((star_g, n));
        } else {
            return false;
        }
    }
    glob[g..].iter().all(|&c| c == '*')
}

#[cfg(test)]
mod tests {
    use super::*;

    fn chars(value: &str) -> Vec<char> {
        value.chars().collect()
    }

    #[test]
    fn glob_matches_like_the_dart_regex() {
        assert!(glob_matches(&chars("*.TMP"), &chars("A.TMP")));
        assert!(glob_matches(&chars("*.TMP"), &chars(".TMP")));
        assert!(!glob_matches(&chars("*.TMP"), &chars("A.TMP.BAK")));
        assert!(glob_matches(&chars("THUMBS?.DB"), &chars("THUMBS1.DB")));
        assert!(!glob_matches(&chars("THUMBS?.DB"), &chars("THUMBS.DB")));
        assert!(glob_matches(&chars("*"), &chars("")));
        assert!(glob_matches(&chars("A*B*C"), &chars("AXXBYYC")));
    }
}
