//! How a backend asks the user for secrets.
//!
//! The backend (the NetworkManager secret agent, or the fake backend) holds a `Prompter` and calls
//! `ask()`; the hub (rpc.rs) receives the request and passes it to the SecretPrompter the shell
//! registered, then returns the answer. Without a registered prompter the answer is `Cancelled`, the
//! same as a user who closed the dialog: NetworkManager ends the attempt with "no secrets".
//!
//! `cancel()` is for NetworkManager's CancelGetSecrets: the dialog of the request is closed and the
//! pending `ask()` is answered as cancelled.

use tokio::sync::{mpsc, oneshot};

use crate::settings::{SecretReply, SecretRequest};

pub enum PromptMessage {
    Ask { request: SecretRequest, reply: oneshot::Sender<SecretReply> },
    Cancel(String),
}

#[derive(Clone)]
pub struct Prompter {
    sender: mpsc::UnboundedSender<PromptMessage>,
}

impl Prompter {
    pub fn new() -> (Prompter, mpsc::UnboundedReceiver<PromptMessage>) {
        let (sender, receiver) = mpsc::unbounded_channel();
        (Prompter { sender }, receiver)
    }

    /// Asks the user; never fails: anything that goes wrong is a cancelled request
    pub async fn ask(&self, request: SecretRequest) -> SecretReply {
        let (reply, answer) = oneshot::channel();
        if self.sender.send(PromptMessage::Ask { request, reply }).is_err() {
            return SecretReply::Cancelled;
        }
        answer.await.unwrap_or(SecretReply::Cancelled)
    }

    pub fn cancel(&self, id: &str) {
        let _ = self.sender.send(PromptMessage::Cancel(id.to_string()));
    }
}
