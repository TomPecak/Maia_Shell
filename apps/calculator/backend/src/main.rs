
mod engine;
mod store;

use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::{Rc, Weak};

use store::{MemoryAction, Store};


struct Listener<C> {
    id: u64,
    format: NumberFormat,
    client: C,
}
struct Shared {
    store: Store,
    history_listeners: Vec<Listener<history_listener::Client>>,
    memory_listeners: Vec<Listener<memory_listener::Client>>,
    next_listener: u64,
}

fn socket_path() -> PathBuf {
    if let Ok(path) = std::env::var("TEST_IPC_CALCULATOR_SOCKET") {
        return PathBuf::from(path);
    }
    let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(runtime).join("test-ipc-calculator.sock")
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("Hello, world one!");

    let path = socket_path();
    let _ = std::fs::remove_file(&path);
    let listener = tokio::net::UnixListener::bind(&path)?;

    let socket_inode: u64 = std::os::unix::fs::MetadataExt::ino(&std::fs::metadata(&path)?);
    println!("calculator-service {} nasłuchuje na {}", env!("CARGO_PKG_VERSION"), path.display());

    let state_file: Option<PathBuf> = dirs::data_dir().map(|dir| dir.join("test-ipc-calculator").join("state.json"));

    let shared = Rc::new(RefCell::new(Shared {
        store: Store::load(state_file),
                                      history_listeners: Vec::new(),
                                      memory_listeners: Vec::new(),
                                      next_listener: 0,
    }));

    println!("{}", path.display());

    println!("Hello, world two!");

    Ok(())
}
