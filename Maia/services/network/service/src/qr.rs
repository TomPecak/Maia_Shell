//! Sharing a Wi-Fi network by QR code (docs/gnome-wifi-features.md, #15).
//!
//! The text is the usual Wi-Fi format phones understand, as GNOME writes it:
//! `WIFI:S:<ssid>;T:<WPA|SAE|WEP|nopass>;P:<password>;H:true;;` (H only for hidden networks), with
//! `\ ; , : "` escaped by a backslash.

use qrcodegen::{QrCode as Encoder, QrCodeEcc};

use crate::backend::{ErrorCode, OpError, OpResult};
use crate::model::{SavedConnection, Security};
use crate::settings::{Secret, SecretKey, find_secret};

pub struct QrCode {
    pub text: String,
    /// Modules per side
    pub size: u32,
    /// size x size, row by row, 1 = dark
    pub modules: Vec<u8>,
}

fn escape(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for c in value.chars() {
        if matches!(c, '\\' | ';' | ',' | ':' | '"') {
            escaped.push('\\');
        }
        escaped.push(c);
    }
    escaped
}

/// The QR text of a saved network
pub fn wifi_text(connection: &SavedConnection, secrets: &[Secret]) -> OpResult<String> {
    let (kind, password) = match connection.security {
        Security::None | Security::EnhancedOpen => ("nopass", ""),
        Security::WpaPersonal => ("WPA", find_secret(secrets, SecretKey::WifiPassword).unwrap_or("")),
        Security::Wpa3Personal => ("SAE", find_secret(secrets, SecretKey::WifiPassword).unwrap_or("")),
        Security::Wep => ("WEP", find_secret(secrets, SecretKey::WepKey).unwrap_or("")),
        _ => return Err(OpError::new(ErrorCode::NotSupported, "no QR code for this security type")),
    };
    let mut text = format!("WIFI:S:{};T:{kind};", escape(&connection.ssid_text()));
    if !password.is_empty() {
        text.push_str(&format!("P:{};", escape(password)));
    }
    if connection.hidden {
        text.push_str("H:true;");
    }
    text.push(';');
    Ok(text)
}

/// The QR text and its matrix (error correction M, as phones read it well from a screen)
pub fn wifi_code(connection: &SavedConnection, secrets: &[Secret]) -> OpResult<QrCode> {
    let text = wifi_text(connection, secrets)?;
    encode(text)
}

pub fn encode(text: String) -> OpResult<QrCode> {
    let qr = Encoder::encode_text(&text, QrCodeEcc::Medium)
        .map_err(|_| OpError::new(ErrorCode::InvalidArgument, "too long for a QR code"))?;
    let size = qr.size();
    let mut modules = Vec::with_capacity((size * size) as usize);
    for y in 0..size {
        for x in 0..size {
            modules.push(u8::from(qr.get_module(x, y)));
        }
    }
    Ok(QrCode { text, size: size as u32, modules })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn connection(ssid: &str, security: Security, hidden: bool) -> SavedConnection {
        SavedConnection { ssid: ssid.as_bytes().to_vec(), security, hidden, ..Default::default() }
    }

    #[test]
    fn personal_networks_carry_the_password_escaped() {
        let secrets = [Secret { key: SecretKey::WifiPassword, value: "a;b:c".into() }];
        let text = wifi_text(&connection("Home, sweet", Security::WpaPersonal, false), &secrets).unwrap();
        assert_eq!(text, r"WIFI:S:Home\, sweet;T:WPA;P:a\;b\:c;;");
    }

    #[test]
    fn open_and_hidden_networks() {
        assert_eq!(wifi_text(&connection("Cafe", Security::None, false), &[]).unwrap(), "WIFI:S:Cafe;T:nopass;;");
        let secrets = [Secret { key: SecretKey::WifiPassword, value: "12345678".into() }];
        assert_eq!(
            wifi_text(&connection("Lab", Security::Wpa3Personal, true), &secrets).unwrap(),
            "WIFI:S:Lab;T:SAE;P:12345678;H:true;;"
        );
    }

    #[test]
    fn the_matrix_is_square_with_finder_patterns() {
        let code = encode("WIFI:S:Cafe;T:nopass;;".into()).unwrap();
        assert!(code.size >= 21);
        assert_eq!(code.modules.len(), (code.size * code.size) as usize);
        // The top left finder pattern: a dark 7x7 frame
        let at = |x: u32, y: u32| code.modules[(y * code.size + x) as usize];
        assert_eq!((0..7).map(|x| at(x, 0)).collect::<Vec<_>>(), vec![1; 7]);
        assert_eq!(at(1, 1), 0);
        assert_eq!(at(3, 3), 1);
    }

    #[test]
    fn enterprise_networks_cannot_be_shared() {
        assert!(wifi_text(&connection("Corp", Security::WpaEnterprise, false), &[]).is_err());
    }
}
