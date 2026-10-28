// Generates the Rust code of the contract ../contract/windows.capnp with the Cap'n Proto compiler.
//
// The CMake build passes the compiler it built from 3rdparty/capnproto (MAIA_CAPNP_EXECUTABLE) and
// the directory of the standard schemas such as capnp/c++.capnp (MAIA_CAPNP_IMPORT_DIR); see
// cmake/MaiaCapnProto.cmake. A plain `cargo build` takes `capnp` from PATH and the standard schemas
// from 3rdparty/capnproto. Schemas installed elsewhere (/usr/include, /usr/local/include) are never
// used, so the result does not depend on what else is installed on the machine.

use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=../contract/windows.capnp");
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
        .import_path(import_dir)
        .src_prefix("../contract")
        .file("../contract/windows.capnp")
        .run()
        .expect("compiling the schema windows.capnp");
}
