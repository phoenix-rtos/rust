use crate::spec::{Cc, Env, LinkerFlavor, Lld, Os, RelocModel, TargetOptions, cvs};

pub(crate) fn opts() -> TargetOptions {
    TargetOptions {
        os: Os::Phoenix,
        env: Env::Libphoenix,
        families: cvs!["unix"],
        linker_flavor: LinkerFlavor::Gnu(Cc::Yes, Lld::No),
        dynamic_linking: false,
        position_independent_executables: false,
        static_position_independent_executables: false,
        relocation_model: RelocModel::Static,
        crt_static_default: true,
        crt_static_respected: false,
        has_thread_local: true,
        ..Default::default()
    }
}
