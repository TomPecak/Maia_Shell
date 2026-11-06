// Generates the Rust code of the contract (../contract/*.capnp) with the Cap'n Proto compiler.
//
// As in the other Maia services: the CMake build passes the compiler it built from
// 3rdparty/capnproto (MAIA_CAPNP_EXECUTABLE) and the directory of the standard schemas
// (MAIA_CAPNP_IMPORT_DIR); see cmake/MaiaCapnProto.cmake. A plain `cargo build` takes `capnp` from
// PATH and the standard schemas from 3rdparty/capnproto.

use std::env;
use std::path::PathBuf;

const SCHEMAS: [&str; 3] = ["common.capnp", "decorations.capnp", "appearance.capnp"];

fn main() {
    for schema in SCHEMAS {
        println!("cargo:rerun-if-changed=../contract/{schema}");
    }
    println!("cargo:rerun-if-env-changed=MAIA_CAPNP_EXECUTABLE");
    println!("cargo:rerun-if-env-changed=MAIA_CAPNP_IMPORT_DIR");

    let import_dir = env::var_os("MAIA_CAPNP_IMPORT_DIR").map(PathBuf::from).unwrap_or_else(|| {
        let crate_dir = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
        crate_dir.join("../../../../3rdparty/capnproto/upstream/src")
    });

    let mut command = capnpc::CompilerCommand::new();
    if let Some(executable) = env::var_os("MAIA_CAPNP_EXECUTABLE") {
        println!("cargo:rerun-if-changed={}", PathBuf::from(&executable).display());
        command.capnp_executable(executable);
    }
    command.no_standard_import().import_path(import_dir).src_prefix("../contract");
    for schema in SCHEMAS {
        command.file(format!("../contract/{schema}"));
    }
    command.run().expect("compiling the appearance schemas");
}
