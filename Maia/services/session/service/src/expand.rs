//! `${NAME}` and `${NAME:-default}` in the values of session.toml.
//!
//! Only these two forms, as in the shell: `${NAME}` is the variable or "" when it is unset or empty,
//! `${NAME:-default}` the default then (the default may contain more of them). A `$` not followed
//! by `{` stays as it is, so `$MAIA_SESSION_SCRIPT` in a compositor's own configuration is not
//! touched here.

/// Expands `text` with `lookup` (the environment of the service, or a map in tests)
pub fn expand(text: &str, lookup: &dyn Fn(&str) -> Option<String>) -> Result<String, String> {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find("${") {
        out.push_str(&rest[..start]);
        let inner_start = start + 2;
        let end = matching_brace(&rest[inner_start..])
            .ok_or_else(|| format!("unclosed ${{ in \"{text}\""))?
            + inner_start;
        let inner = &rest[inner_start..end];
        let (name, default) = match inner.find(":-") {
            Some(i) => (&inner[..i], Some(&inner[i + 2..])),
            None => (inner, None),
        };
        if name.is_empty() || !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
            return Err(format!("bad variable name \"{name}\" in \"{text}\""));
        }
        match lookup(name).filter(|value| !value.is_empty()) {
            Some(value) => out.push_str(&value),
            None => {
                if let Some(default) = default {
                    out.push_str(&expand(default, lookup)?);
                }
            }
        }
        rest = &rest[end + 1..];
    }
    out.push_str(rest);
    Ok(out)
}

/// The position of the `}` that closes a `${` whose inside starts at text[0]
fn matching_brace(text: &str) -> Option<usize> {
    let mut depth = 0usize;
    let bytes = text.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'$' if bytes.get(i + 1) == Some(&b'{') => {
                depth += 1;
                i += 1;
            }
            b'}' if depth == 0 => return Some(i),
            b'}' => depth -= 1,
            _ => {}
        }
        i += 1;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env(name: &str) -> Option<String> {
        match name {
            "PREFIX" => Some("/opt/Maia/Maia_0.2.0".into()),
            "EMPTY" => Some(String::new()),
            "VERSION" => Some("0.2.0".into()),
            _ => None,
        }
    }

    #[test]
    fn plain_variables() {
        assert_eq!(expand("${PREFIX}/bin/x", &env).unwrap(), "/opt/Maia/Maia_0.2.0/bin/x");
        assert_eq!(expand("maia_${VERSION}_server.log", &env).unwrap(), "maia_0.2.0_server.log");
        assert_eq!(expand("a${UNSET}b", &env).unwrap(), "ab");
        assert_eq!(expand("no variables", &env).unwrap(), "no variables");
    }

    #[test]
    fn defaults_nest() {
        assert_eq!(expand("${UNSET:-${PREFIX}/libexec/s}", &env).unwrap(), "/opt/Maia/Maia_0.2.0/libexec/s");
        assert_eq!(expand("${EMPTY:-fallback}", &env).unwrap(), "fallback");
        assert_eq!(expand("${VERSION:-fallback}", &env).unwrap(), "0.2.0");
        assert_eq!(expand("${UNSET:-}", &env).unwrap(), "");
    }

    #[test]
    fn a_dollar_without_brace_stays() {
        assert_eq!(expand("$MAIA_SESSION_SCRIPT", &env).unwrap(), "$MAIA_SESSION_SCRIPT");
    }

    #[test]
    fn mistakes_are_reported() {
        assert!(expand("${PREFIX", &env).is_err());
        assert!(expand("${BAD NAME}", &env).is_err());
        assert!(expand("${}", &env).is_err());
    }
}
