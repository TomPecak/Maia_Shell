//! Errors of operations, the values of the contract's ErrorCode (common.capnp).

use std::fmt;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ErrorCode {
    NotFound,
    NotAllowed,
    InvalidArgument,
    NotSupported,
    Unavailable,
    Failed,
    AlreadyExists,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpError {
    pub code: ErrorCode,
    /// For logs, not for users
    pub message: String,
}

impl OpError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self { code, message: message.into() }
    }

    pub fn invalid(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::InvalidArgument, message)
    }

    pub fn failed(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::Failed, message)
    }

    pub fn io(what: &str, error: std::io::Error) -> Self {
        let code = match error.kind() {
            std::io::ErrorKind::NotFound => ErrorCode::NotFound,
            std::io::ErrorKind::PermissionDenied => ErrorCode::NotAllowed,
            std::io::ErrorKind::AlreadyExists => ErrorCode::AlreadyExists,
            _ => ErrorCode::Failed,
        };
        Self::new(code, format!("{what}: {error}"))
    }
}

impl fmt::Display for OpError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}: {}", self.code, self.message)
    }
}

impl std::error::Error for OpError {}

pub type OpResult<T = ()> = Result<T, OpError>;
