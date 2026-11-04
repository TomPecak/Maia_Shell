# Maia network service

Wi-Fi for shells, Maia Settings and apps. One process talks to NetworkManager; every client gets
the state and changes it through a Cap'n Proto contract.

```text
 NetworkManager ──D-Bus (zbus)──► maia-network-service ──Cap'n Proto──► Maia.Network (QML)
 (system bus)                     (service/, Rust)                       Lumen's quick settings,
   ◄── connect, scan, ... ───────                ◄── control ─────────── the Maia frontend,
   ── GetSecrets ──► secret agent ── SecretPrompter ──► the shell's      Maia Settings
                                                        password dialog
```

What the interface offers, feature by feature, is in [docs/gnome-wifi-features.md](docs/gnome-wifi-features.md)
(taken from GNOME); the contract refers to its numbers.

## Layout

| Path | What |
|---|---|
| `contract/network.capnp` | The contract: `NetworkService` (info, watch, control, registerPrompter), `NetworkListener`, `NetworkControl`, `SecretPrompter`. Read it first. |
| `service/` | `maia-network-service` (Rust, tokio, one thread). |
| `service/src/model.rs` | The state as plain values; access points merged into networks (pure logic). |
| `service/src/settings.rs` | Connection settings, secrets, password requests and their checks. |
| `service/src/backend.rs` | What a backend and the hub exchange (channels). |
| `service/src/nm.rs`, `nmdefs.rs` | The NetworkManager backend; NetworkManager's numbers (states, reasons, flags). |
| `service/src/nmsettings.rs` | NetworkManager profiles (`a{sa{sv}}`) to and from the contract's settings and secrets; new hidden, Enterprise and hotspot profiles. Edits keep the keys Maia does not know. |
| `service/src/agent.rs` | The secret agent NetworkManager asks for passwords. |
| `service/src/fake.rs` | A simulated NetworkManager for tests and interface work. |
| `service/src/rpc.rs` | The Cap'n Proto server: snapshot, then changes, to every listener; control; the prompter. |
| `service/src/prompt.rs` | How a backend asks the user for secrets (through the hub to the shell). |
| `service/src/throttle.rs` | At most one change per object every 250 ms (signal strengths change all the time). |
| `service/src/qr.rs` | The QR code of a network for sharing: its text and matrix (`qrcodegen`, error correction M). |
| `service/tests/service.rs` | The service over a real Cap'n Proto connection with the fake backend. |
| `service/examples/watch.rs` | Prints the served state and its changes; sends no command. |
| `service/examples/profiles.rs` | Prints the Wi-Fi profiles of the real NetworkManager as the details editor reads them (GetSettings only: no secrets, no agent). |

## Running it

The session script starts it (`libexec/maia-network-service`). By hand:

```bash
# Simulated network: nothing reaches the real one
MAIA_NETWORK_BACKEND=fake MAIA_NETWORK_SOCKET=$XDG_RUNTIME_DIR/maia/net-test.sock maia-network-service
# What it serves
cargo run --example watch -- $XDG_RUNTIME_DIR/maia/net-test.sock
```

| Variable | Meaning |
|---|---|
| `MAIA_NETWORK_BACKEND` | `networkmanager` (default) or `fake` |
| `MAIA_NETWORK_SOCKET` | the socket; default `$XDG_RUNTIME_DIR/maia/network-$WAYLAND_DISPLAY.sock` |

The nested development session (`run_maia_nested_wayland.sh`) starts it with the **fake** backend:
there the real NetworkManager is the network of the machine, and its secret agent belongs to the
main session. `MAIA_NETWORK_BACKEND=networkmanager` overrides that, knowingly.

## Passwords

The service is the secret agent of the session (`agent.rs`). When NetworkManager needs secrets it
asks the agent, the agent asks the shell through the `SecretPrompter` it registered, the shell
shows its password dialog. Secrets are kept by NetworkManager in the profile (owned by the system,
readable by root only), as `nmcli` does: KWallet is off in Maia, so there is no other store.
The KDE agent (kded module `networkmanagement`) is kept from loading in Maia sessions by
`Maia/DeployFiles/etc/xdg/kded6rc`, so that only one agent answers.

## Testing

```bash
cd service && cargo test        # 23 unit tests, 10 over Cap'n Proto with the fake backend
```

Every action against the real NetworkManager changes the network of the machine; tests and
interface work use the fake backend. Only reading (`watch`) is safe against the real one.

## Not done yet

- Maia Settings and its Wi-Fi page (`apps/settings/pages/network/`).
