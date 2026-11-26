//! Texts of items as plain text.
//!
//! The specification allows a subset of HTML in a tool tip (KDE applications use <b>, <br/>,
//! entities), and some applications put markup in titles too. The shells get plain text only: tags
//! go (a line break and a paragraph become a new line), entities are decoded, spaces are collapsed.
//! Text that only looks like markup ("a < b") stays as it is.

/// Plain text of several lines
pub fn plain(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut rest = input;
    // Inside <script> or <style>: their content is not text
    let mut skipping: Option<String> = None;
    while let Some(c) = rest.chars().next() {
        if c == '<' {
            if let Some((tag, closing, len)) = tag_at(rest) {
                rest = &rest[len..];
                match &skipping {
                    Some(skipped) if closing && *skipped == tag => skipping = None,
                    Some(_) => {}
                    None if !closing && (tag == "script" || tag == "style") => skipping = Some(tag),
                    None if tag == "br" => out.push('\n'),
                    // A block starts on a line of its own
                    None if !closing && matches!(tag.as_str(), "p" | "div" | "li" | "tr") && !out.is_empty() && !out.ends_with('\n') => {
                        out.push('\n')
                    }
                    None => {}
                }
                continue;
            }
        }
        rest = &rest[c.len_utf8()..];
        if skipping.is_some() {
            continue;
        }
        if c == '&' {
            if let Some((decoded, len)) = entity_at(&rest[..]) {
                out.push(decoded);
                rest = &rest[len..];
                continue;
            }
        }
        out.push(if c == '\r' || c == '\t' { ' ' } else { c });
    }
    tidy(&out)
}

/// Plain text of one line (a title)
pub fn line(input: &str) -> String {
    plain(input).replace('\n', " ")
}

/// At most `max` characters; a cut text ends with "…"
pub fn limit_chars(text: String, max: usize) -> String {
    match text.char_indices().nth(max) {
        Some((cut, _)) => {
            let mut text = text;
            text.truncate(cut);
            text.push('…');
            text
        }
        None => text,
    }
}

/// A tag at the start of `s` ("<b>", "</p>", "<br/>", "<a href=…>"): its lower-case name, whether
/// it closes, and its length. None when the "<" does not start a tag.
fn tag_at(s: &str) -> Option<(String, bool, usize)> {
    let body = &s[1..];
    let closing = body.starts_with('/');
    let name_start = if closing { &body[1..] } else { body };
    let name: String = name_start.chars().take_while(|c| c.is_ascii_alphanumeric()).collect();
    if name.is_empty() || !name.starts_with(|c: char| c.is_ascii_alphabetic()) {
        return None;
    }
    let end = s.find('>')?;
    // A "<" inside means it was not a tag ("a <b c <d>")
    if s[1..end].contains('<') {
        return None;
    }
    Some((name.to_ascii_lowercase(), closing, end + 1))
}

/// An entity right after an "&" ("amp;", "#39;", "#x27;"): the character and the length after "&"
fn entity_at(s: &str) -> Option<(char, usize)> {
    let end = s.find(';')?;
    if end == 0 || end > 10 {
        return None;
    }
    let inner = &s[..end];
    let c = match inner {
        "amp" => '&',
        "lt" => '<',
        "gt" => '>',
        "quot" => '"',
        "apos" => '\'',
        "nbsp" => ' ',
        _ => {
            let code = if let Some(hex) = inner.strip_prefix("#x").or_else(|| inner.strip_prefix("#X")) {
                u32::from_str_radix(hex, 16).ok()?
            } else {
                inner.strip_prefix('#')?.parse::<u32>().ok()?
            };
            char::from_u32(code).filter(|c| !c.is_control() || *c == '\n')?
        }
    };
    Some((c, end + 1))
}

/// Spaces collapsed in each line, empty lines at the ends and doubled ones in the middle removed
fn tidy(text: &str) -> String {
    let mut lines: Vec<String> = Vec::new();
    for raw in text.split('\n') {
        let line = raw.split(' ').filter(|w| !w.is_empty()).collect::<Vec<_>>().join(" ");
        if line.is_empty() && lines.last().is_none_or(|l| l.is_empty()) {
            continue;
        }
        lines.push(line);
    }
    while lines.last().is_some_and(|l| l.is_empty()) {
        lines.pop();
    }
    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tags_go_and_breaks_become_lines() {
        assert_eq!(plain("<b>3</b> new messages<br/>in <i>Inbox</i>"), "3 new messages\nin Inbox");
        assert_eq!(plain("<p>One</p><p>Two</p>"), "One\nTwo");
        assert_eq!(plain("<a href=\"https://kde.org\">KDE</a>"), "KDE");
        assert_eq!(plain("a<script>alert(1)</script>b<style>p{}</style>c"), "abc");
    }

    #[test]
    fn text_that_only_looks_like_markup_stays() {
        assert_eq!(plain("a < b && c > d"), "a < b && c > d");
        assert_eq!(plain("x<3"), "x<3");
        assert_eq!(plain("<3 you"), "<3 you");
    }

    #[test]
    fn entities_are_decoded() {
        assert_eq!(plain("Tom &amp; Jerry &lt;3&gt; &#39;x&#x27;"), "Tom & Jerry <3> 'x'");
        assert_eq!(plain("&unknown; &"), "&unknown; &");
    }

    #[test]
    fn spaces_and_empty_lines_are_tidied() {
        assert_eq!(plain("  a \t b \r\n\n\n c  \n\n"), "a b\n\nc");
        assert_eq!(line("Volume<br>50 %"), "Volume 50 %");
    }

    #[test]
    fn long_texts_are_cut() {
        assert_eq!(limit_chars("abcdef".into(), 3), "abc…");
        assert_eq!(limit_chars("żółw".into(), 4), "żółw");
    }
}
