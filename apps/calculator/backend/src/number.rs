use std::str::FromStr;




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