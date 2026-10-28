//! Starting applications from their desktop entries (Exec=).
//!
//! Exec= is split into words like the desktop entry specification says (double quotes, backslash
//! escapes inside them), field codes are expanded or dropped (no files or URLs are passed here).
//! The program runs in its own process group, so it outlives a restart of the service; the service
//! only waits for it to reap it.

use crate::apps::AppInfo;

/// Splits Exec= into words (quoting rules of the desktop entry specification)
pub fn split_exec(exec: &str) -> Vec<String> {
    let mut words = Vec::new();
    let mut word = String::new();
    let mut in_word = false;
    let mut chars = exec.chars();
    while let Some(c) = chars.next() {
        match c {
            '"' => {
                in_word = true;
                while let Some(q) = chars.next() {
                    match q {
                        '"' => break,
                        '\\' => {
                            if let Some(escaped) = chars.next() {
                                word.push(escaped);
                            }
                        }
                        other => word.push(other),
                    }
                }
            }
            ' ' | '\t' => {
                if in_word {
                    words.push(std::mem::take(&mut word));
                    in_word = false;
                }
            }
            other => {
                in_word = true;
                word.push(other);
            }
        }
    }
    if in_word {
        words.push(word);
    }
    words
}

/// The command line of an application: Exec= with the field codes expanded (%i, %c) or dropped
pub fn command_line(app: &AppInfo) -> Vec<String> {
    let mut args = Vec::new();
    for word in split_exec(&app.exec) {
        match word.as_str() {
            "%f" | "%F" | "%u" | "%U" | "%d" | "%D" | "%n" | "%N" | "%k" | "%v" | "%m" => {}
            "%i" => {
                if !app.icon.is_empty() {
                    args.push("--icon".to_string());
                    args.push(app.icon.clone());
                }
            }
            "%c" => args.push(app.name.clone()),
            _ => args.push(word.replace("%%", "%")),
        }
    }
    args
}

/// Starts the application; returns an error when there is nothing to start or it cannot be started.
/// Must run inside the tokio LocalSet of the service (the reaping task is local).
pub fn launch(app: &AppInfo) -> std::io::Result<()> {
    let args = command_line(app);
    let Some((program, rest)) = args.split_first() else {
        return Err(std::io::Error::other(format!("{} has no Exec=", app.desktop_id)));
    };
    let mut child = tokio::process::Command::new(program)
        .args(rest)
        .stdin(std::process::Stdio::null())
        .process_group(0)
        .spawn()?;
    tokio::task::spawn_local(async move {
        let _ = child.wait().await;
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_with_quotes_and_escapes() {
        assert_eq!(split_exec(r#"kate -b %U"#), ["kate", "-b", "%U"]);
        assert_eq!(split_exec(r#""/opt/My App/run" --name "a \"b\"""#), ["/opt/My App/run", "--name", r#"a "b""#]);
        assert!(split_exec("   ").is_empty());
    }

    #[test]
    fn expands_and_drops_field_codes() {
        let app = AppInfo {
            exec: "konsole %i --title %c %U 100%%".into(),
            icon: "utilities-terminal".into(),
            name: "Konsole".into(),
            ..Default::default()
        };
        assert_eq!(command_line(&app), ["konsole", "--icon", "utilities-terminal", "--title", "Konsole", "100%"]);
    }
}
