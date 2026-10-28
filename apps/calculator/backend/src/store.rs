use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::engine::Calculation;


const HISTORY_LIMIT: usize = 100;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HistoryEntry {
    pub id: u64,
    pub calculation: Calculation,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct State {
    history: Vec<HistoryEntry>,
    memory: Vec<Num>,
    next_id: u64,
}

pub enum MemoryAction {
    Recall,
    Add,
    Subtract,
    Clear,
}

pub struct Store {
    state: State,
    path: Option<PathBuf>,
}
