// Generates the Rust code of the contract ../contract/power.capnp, and of the notification service's
// contract (the power service is its client), with the Cap'n Proto compiler.
//
// The CMake build passes the compiler it built from 3rdparty/capnproto (MAIA_CAPNP_EXECUTABLE) and
// the directory of the standard schemas such as capnp/c++.capnp (MAIA_CAPNP_IMPORT_DIR); see
// cmake/MaiaCapnProto.cmake. A plain `cargo build` takes `capnp` from PATH and the standard schemas
// from 3rdparty/capnproto. Schemas installed elsewhere (/usr/include, /usr/local/include) are never
// used, so the result does not depend on what else is installed on the machine.

use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=../contract/power.capnp");
    println!("cargo:rerun-if-env-changed=MAIA_CAPNP_EXECUTABLE");
    println!("cargo:rerun-if-env-changed=MAIA_CAPNP_IMPORT_DIR");

    let import_dir = env::var_os("MAIA_CAPNP_IMPORT_DIR").map(PathBuf::from).unwrap_or_else(|| {
        let crate_dir = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
        crate_dir.join("../../../../3rdparty/capnproto/upstream/src")
    });

    let mut command = capnpc::CompilerCommand::new();
    if let Some(executable) = env::var_os("MAIA_CAPNP_EXECUTABLE") {
        // A rebuilt compiler (e.g. a new Cap'n Proto version) regenerates the code
        println!("cargo:rerun-if-changed={}", PathBuf::from(&executable).display());
        command.capnp_executable(executable);
    }
    command
        .no_standard_import()
        .import_path(&import_dir)
        .src_prefix("../contract")
        .file("../contract/power.capnp")
        .run()
        .expect("compiling the schema power.capnp");

    // The notification service's contract: the power service sends its battery warnings as a
    // Notifier client
    println!("cargo:rerun-if-changed=../../notifications/contract/notifications.capnp");
    let mut command = capnpc::CompilerCommand::new();
    if let Some(executable) = env::var_os("MAIA_CAPNP_EXECUTABLE") {
        command.capnp_executable(executable);
    }
    command
        .no_standard_import()
        .import_path(&import_dir)
        .src_prefix("../../notifications/contract")
        .file("../../notifications/contract/notifications.capnp")
        .run()
        .expect("compiling the schema notifications.capnp");
}
