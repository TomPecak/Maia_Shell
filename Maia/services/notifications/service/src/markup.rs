//! The body of a notification made safe for the shells.
//!
//! The specification allows a little HTML in the body (capability "body-markup"): <b>, <i>, <u>,
//! <a href="…"> and <img>. Applications send everything from plain text with "<" and "&" in it to
//! whole HTML. What the shells get is always well formed and harmless (Qt's StyledText shows it):
//!
//! - <b>, <i>, <u>, <br> stay; <a> stays with an href of http(s), mailto or file; every open tag is
//!   closed at the end, stray closing tags go;
//! - any other tag (<img>, <p>, <span>, <script>…) goes, its text stays (the content of <script>
//!   and <style> goes too);
//! - "<" that does not start a tag ("a < b"), ">" and "&" that is not an entity become entities;
//! - line breaks become <br/>.

const KEPT: [&str; 4] = ["b", "i", "u", "a"];
const DROPPED_WITH_CONTENT: [&str; 2] = ["script", "style"];
const SCHEMES: [&str; 4] = ["http://", "https://", "mailto:", "file://"];

struct Tag {
    name: String,
    closing: bool,
    self_closing: bool,
    attributes: String,
    /// Bytes from '<' to '>' inclusive
    len: usize,
}

/// Reads a tag at the start of `s` (which starts with '<'), if it is one
fn parse_tag(s: &str) -> Option<Tag> {
    let bytes = s.as_bytes();
    let mut i = 1;
    let closing = bytes.get(i) == Some(&b'/');
    if closing {
        i += 1;
    }
    let name_start = i;
    while i < bytes.len() && (bytes[i].is_ascii_alphanumeric()) {
        i += 1;
    }
    if i == name_start || !bytes[name_start].is_ascii_alphabetic() {
        return None;
    }
    let name = s[name_start..i].to_ascii_lowercase();
    // Attributes up to '>', honouring quotes
    let attr_start = i;
    let mut quote: Option<u8> = None;
    while i < bytes.len() {
        match (quote, bytes[i]) {
            (None, b'>') => break,
            (None, b'<') => return None,
            (None, q @ (b'"' | b'\'')) => quote = Some(q),
            (Some(q), c) if c == q => quote = None,
            _ => {}
        }
        i += 1;
    }
    if i >= bytes.len() {
        return None;
    }
    if attr_start < i && !bytes[attr_start].is_ascii_whitespace() && bytes[attr_start] != b'/' {
        return None;
    }
    let mut attributes = s[attr_start..i].trim().to_string();
    let self_closing = attributes.ends_with('/');
    if self_closing {
        attributes.pop();
    }
    Some(Tag { name, closing, self_closing, attributes, len: i + 1 })
}

/// The value of attribute `name` in `attributes`, entities left as they are
fn attribute(attributes: &str, name: &str) -> Option<String> {
    let lower = attributes.to_ascii_lowercase();
    let mut from = 0;
    while let Some(found) = lower[from..].find(name) {
        let at = from + found;
        let before_ok = at == 0 || lower.as_bytes()[at - 1].is_ascii_whitespace();
        let rest = attributes[at + name.len()..].trim_start();
        if before_ok && rest.starts_with('=') {
            let value = rest[1..].trim_start();
            return match value.chars().next() {
                Some(q @ ('"' | '\'')) => value[1..].find(q).map(|end| value[1..1 + end].to_string()),
                Some(_) => Some(value.split_whitespace().next().unwrap_or("").to_string()),
                None => None,
            };
        }
        from = at + name.len();
    }
    None
}

/// Whether `s` (which starts with '&') starts with an entity
fn entity_len(s: &str) -> Option<usize> {
    let end = s.find(';')?;
    if end > 12 {
        return None;
    }
    let inner = &s[1..end];
    let valid = matches!(inner, "amp" | "lt" | "gt" | "quot" | "apos" | "nbsp")
        || inner.strip_prefix("#x").or_else(|| inner.strip_prefix("#X")).is_some_and(|h| !h.is_empty() && h.chars().all(|c| c.is_ascii_hexdigit()))
        || inner.strip_prefix('#').is_some_and(|d| !d.is_empty() && d.chars().all(|c| c.is_ascii_digit()));
    valid.then_some(end + 1)
}

fn escape_attribute(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        match c {
            '"' => out.push_str("&quot;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '&' => out.push_str("&amp;"),
            c => out.push(c),
        }
    }
    out
}

/// The body made safe (see the module's documentation)
pub fn sanitize(input: &str) -> String {
    let mut out = String::with_capacity(input.len() + 16);
    let mut open: Vec<&'static str> = Vec::new();
    let mut skipping: Option<String> = None;
    let mut i = 0;
    while i < input.len() {
        let rest = &input[i..];
        let c = rest.chars().next().unwrap();
        if let Some(name) = &skipping {
            // Inside <script> or <style>: only its end matters
            if c == '<' {
                if let Some(tag) = parse_tag(rest) {
                    if tag.closing && &tag.name == name {
                        skipping = None;
                    }
                    i += tag.len;
                    continue;
                }
            }
            i += c.len_utf8();
            continue;
        }
        match c {
            '<' => match parse_tag(rest) {
                Some(tag) => {
                    i += tag.len;
                    if DROPPED_WITH_CONTENT.contains(&tag.name.as_str()) {
                        if !tag.closing && !tag.self_closing {
                            skipping = Some(tag.name);
                        }
                        continue;
                    }
                    if tag.name == "br" {
                        out.push_str("<br/>");
                        continue;
                    }
                    let Some(&name) = KEPT.iter().find(|&&k| k == tag.name) else { continue };
                    if tag.closing {
                        if let Some(pos) = open.iter().rposition(|&o| o == name) {
                            // Closes what was opened inside it too
                            for inner in open.drain(pos..).rev() {
                                out.push_str("</");
                                out.push_str(inner);
                                out.push('>');
                            }
                        }
                    } else if tag.self_closing {
                        // <b/> means nothing
                    } else if name == "a" {
                        match attribute(&tag.attributes, "href") {
                            Some(href) if SCHEMES.iter().any(|s| href.to_ascii_lowercase().starts_with(s)) => {
                                out.push_str("<a href=\"");
                                out.push_str(&escape_attribute(&href.replace("&amp;", "&")));
                                out.push_str("\">");
                                open.push("a");
                            }
                            // A link to nowhere (or javascript:) is just its text
                            _ => {}
                        }
                    } else {
                        out.push('<');
                        out.push_str(name);
                        out.push('>');
                        open.push(name);
                    }
                }
                None => {
                    out.push_str("&lt;");
                    i += 1;
                }
            },
            '>' => {
                out.push_str("&gt;");
                i += 1;
            }
            '&' => match entity_len(rest) {
                Some(len) => {
                    out.push_str(&rest[..len]);
                    i += len;
                }
                None => {
                    out.push_str("&amp;");
                    i += 1;
                }
            },
            '\r' => i += 1,
            '\n' => {
                out.push_str("<br/>");
                i += 1;
            }
            c => {
                out.push(c);
                i += c.len_utf8();
            }
        }
    }
    for name in open.iter().rev() {
        out.push_str("</");
        out.push_str(name);
        out.push('>');
    }
    out
}

/// Plain text, for a summary: markup is not allowed there, so it is shown as it is
pub fn plain(input: &str) -> String {
    input.replace(['\r', '\n'], " ").trim().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_text_is_escaped() {
        assert_eq!(sanitize("a < b && c > d"), "a &lt; b &amp;&amp; c &gt; d");
        assert_eq!(sanitize("Tom & Jerry"), "Tom &amp; Jerry");
        assert_eq!(sanitize("x<3"), "x&lt;3");
    }

    #[test]
    fn allowed_tags_stay_and_are_closed() {
        assert_eq!(sanitize("<b>Anna</b>: <i>hi</i> <u>u</u>"), "<b>Anna</b>: <i>hi</i> <u>u</u>");
        assert_eq!(sanitize("<B>open"), "<b>open</b>");
        assert_eq!(sanitize("<b><i>x</b> y"), "<b><i>x</i></b> y");
        assert_eq!(sanitize("stray</i>"), "stray");
    }

    #[test]
    fn links_keep_safe_targets_only() {
        assert_eq!(sanitize("<a href=\"https://kde.org\">KDE</a>"), "<a href=\"https://kde.org\">KDE</a>");
        assert_eq!(sanitize("<a href='mailto:a@b.c'>mail</a>"), "<a href=\"mailto:a@b.c\">mail</a>");
        assert_eq!(sanitize("<a href=\"javascript:alert(1)\">x</a>"), "x");
        assert_eq!(sanitize("<a>x</a>"), "x");
        assert_eq!(sanitize("<a href=\"https://x.org/?a=1&b=2\">q</a>"), "<a href=\"https://x.org/?a=1&amp;b=2\">q</a>");
        assert_eq!(sanitize("<a href=\"https://x.org/?a=1&amp;b=2\">q</a>"), "<a href=\"https://x.org/?a=1&amp;b=2\">q</a>");
    }

    #[test]
    fn other_tags_go_but_their_text_stays() {
        assert_eq!(sanitize("<p>Hello <span style=\"color:red\">there</span></p>"), "Hello there");
        assert_eq!(sanitize("<img src=\"x.png\" alt=\"pic\"/>after"), "after");
        assert_eq!(sanitize("a<script>alert(1)</script>b<style>p{}</style>c"), "abc");
    }

    #[test]
    fn entities_stay_and_line_breaks_become_br() {
        assert_eq!(sanitize("&lt;tag&gt; &#169; &#x1F600; &nbsp;"), "&lt;tag&gt; &#169; &#x1F600; &nbsp;");
        assert_eq!(sanitize("&bogus; &"), "&amp;bogus; &amp;");
        assert_eq!(sanitize("one\r\ntwo<br>three<BR/>"), "one<br/>two<br/>three<br/>");
    }

    #[test]
    fn broken_markup_is_text() {
        assert_eq!(sanitize("<b unclosed"), "&lt;b unclosed");
        assert_eq!(sanitize("<<b>x</b>"), "&lt;<b>x</b>");
        assert_eq!(sanitize("<bold>"), "");
        assert_eq!(sanitize("1 <2"), "1 &lt;2");
    }

    #[test]
    fn unicode_passes() {
        assert_eq!(sanitize("Zażółć <b>gęślą</b> jaźń 🙂"), "Zażółć <b>gęślą</b> jaźń 🙂");
    }

    #[test]
    fn summaries_are_one_line() {
        assert_eq!(plain(" Two\nlines "), "Two lines");
    }
}
