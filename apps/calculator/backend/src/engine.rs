use serde::{Deserialize, Serialize};

use crate::number::{CalcError, Num, NumberFormat, localize};

/// Zakończone działanie (do historii)
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Calculation {
    pub parts: Vec<Part>,
    pub result: Num,
}