use std::str::FromStr;

use bigdecimal::{BigDecimal, RoundingMode, Signed, Zero};
use serde::{Deserialize, Deserializer, Serialize, Serializer};

pub const PRECISION: i64 = 34;
pub const DISPLAY_DIGITS: i64 = 16;
const MAX_EXPONENT: i64 = 9999;


#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CalcError {
    DivideByZero,
    Undefined,
    InvalidInput,
    Overflow,
}

impl CalcError {
    pub fn message(self) -> &'static str {
        match self {
            CalcError::DivideByZero => "Cannot divide by zero",
            CalcError::Undefined => "Result is undefined",
            CalcError::InvalidInput => "Invalid input",
            CalcError::Overflow => "Overflow",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NumberFormat {
    pub decimal: String,
    pub group: String,
}

impl Default for NumberFormat {
    fn default() -> Self {
        Self { decimal: ".".into(), group: ",".into() }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Num(BigDecimal);


/// Wykładnik pierwszej cyfry znaczącej: 123,4 -> 2; 0,05 -> -2
fn exponent(v: &BigDecimal) -> i64 {
    let (int, scale) = v.as_bigint_and_exponent();
    int.magnitude().to_string().len() as i64 - 1 - scale
}

fn round_significant(v: &BigDecimal, digits: i64, mode: RoundingMode) -> BigDecimal {
    if v.is_zero() {
        return BigDecimal::zero();
    }
    v.with_scale_round(digits - 1 - exponent(v), mode).normalized()
}

fn plain(v: &BigDecimal) -> String {
    let (int, scale) = v.normalized().as_bigint_and_exponent();
    let digits = int.magnitude().to_string();
    let sign = if int.is_negative() { "-" } else { "" };
    if scale <= 0 {
        return format!("{sign}{digits}{}", "0".repeat((-scale) as usize));
    }
    let scale = scale as usize;
    if digits.len() > scale {
        let (whole, frac) = digits.split_at(digits.len() - scale);
        format!("{sign}{whole}.{frac}")
    } else {
        format!("{sign}0.{}{digits}", "0".repeat(scale - digits.len()))
    }
}

fn group_digits(whole: &str, separator: &str) -> String {
    if separator.is_empty() || whole.len() <= 3 {
        return whole.to_string();
    }
    let mut out = String::new();
    for (i, ch) in whole.chars().enumerate() {
        if i > 0 && (whole.len() - i) % 3 == 0 {
            out.push_str(separator);
        }
        out.push(ch);
    }
    out
}

pub fn localize(text: &str, fmt: &NumberFormat) -> String {
    let (sign, rest) = match text.strip_prefix('-') {
        Some(rest) => ("-", rest),
        None => ("", text),
    };
    match rest.split_once('.') {
        Some((whole, frac)) => format!("{sign}{}{}{frac}", group_digits(whole, &fmt.group), fmt.decimal),
        None => format!("{sign}{}", group_digits(rest, &fmt.group)),
    }
}

impl Num {
    pub fn zero() -> Self {
        Num(BigDecimal::zero())
    }

    pub fn from_i64(v: i64) -> Self {
        Num(BigDecimal::from(v))
    }

    fn checked(v: BigDecimal) -> Result<Num, CalcError> {
        if v.is_zero() {
            return Ok(Num::zero());
        }
        let v = round_significant(&v, PRECISION, RoundingMode::HalfEven);
        let e = exponent(&v);
        if e > MAX_EXPONENT {
            return Err(CalcError::Overflow);
        }
        if e < -MAX_EXPONENT {
            return Ok(Num::zero());
        }
        Ok(Num(v))
    }

    pub fn parse(text: &str) -> Option<Num> {
        let text = text.trim().trim_end_matches('.');
        let valid = !text.is_empty()
            && text.chars().all(|c| c.is_ascii_digit() || matches!(c, '.' | '-' | '+' | 'e' | 'E'))
            && text.chars().any(|c| c.is_ascii_digit());
        if !valid {
            return None;
        }
        BigDecimal::from_str(text).ok().and_then(|v| Num::checked(v).ok())
    }

    pub fn parse_localized(text: &str, fmt: &NumberFormat) -> Option<Num> {
        let mut text: String = text.chars().filter(|c| !c.is_whitespace() && *c != '\u{a0}' && *c != '\u{202f}').collect();
        text = text.replace('\u{2212}', "-");
        if !fmt.group.trim().is_empty() && fmt.group != fmt.decimal {
            text = text.replace(fmt.group.trim(), "");
        }
        if fmt.decimal != "." {
            text = text.replace(&fmt.decimal, ".");
        }
        Num::parse(&text)
    }

    pub fn is_zero(&self) -> bool {
        self.0.is_zero()
    }

    pub fn is_negative(&self) -> bool {
        self.0.is_negative()
    }

    pub fn add(&self, o: &Num) -> Result<Num, CalcError> {
        Num::checked(&self.0 + &o.0)
    }

    pub fn sub(&self, o: &Num) -> Result<Num, CalcError> {
        Num::checked(&self.0 - &o.0)
    }

    pub fn mul(&self, o: &Num) -> Result<Num, CalcError> {
        Num::checked(&self.0 * &o.0)
    }

    pub fn div(&self, o: &Num) -> Result<Num, CalcError> {
        if o.is_zero() {
            return Err(if self.is_zero() { CalcError::Undefined } else { CalcError::DivideByZero });
        }
        Num::checked(&self.0 / &o.0)
    }

    
}