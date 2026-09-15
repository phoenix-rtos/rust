use crate::spec::{
    Arch, Cc, CfgAbi, Env, FloatAbi, LinkerFlavor, Lld, RelocModel, Target, TargetMetadata,
    TlsModel, base,
};

pub(crate) fn target() -> Target {
    let mut opts = base::phoenix::opts();
    opts.linker = Some("arm-phoenix-gcc".into());
    opts.env = Env::LibphoenixNoMmu;
    opts.cfg_abi = CfgAbi::EabiHf;
    opts.llvm_floatabi = Some(FloatAbi::Hard);
    opts.features =
        "+v7,+thumb2,+thumb-mode,+vfp3d16,+strict-align,+read-tp-tpidruro,+reserve-r9".into();
    opts.max_atomic_width = Some(64);
    opts.c_enum_min_bits = Some(8);
    opts.relocation_model = RelocModel::RopiRwpi;
    opts.linker_flavor = LinkerFlavor::Gnu(Cc::Yes, Lld::Yes);
    opts.add_pre_link_args(
        LinkerFlavor::Gnu(Cc::Yes, Lld::No),
        &[
            "-Wl,--pic-veneer",
            "-Wl,--no-warn-mismatch",
            "-Wl,-z,max-page-size=0x1000",
        ],
    );
    opts.tls_model = TlsModel::LocalExec;
    opts.position_independent_executables = true;
    opts.static_position_independent_executables = true;

    Target {
        llvm_target: "armv7r-unknown-phoenix-eabihf".into(),
        metadata: TargetMetadata {
            description: Some("ARMv7-R Cortex-R Phoenix-RTOS (hard float, no MMU)".into()),
            tier: Some(3),
            host_tools: Some(false),
            std: Some(true),
        },
        pointer_width: 32,
        data_layout: "e-m:e-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64".into(),
        arch: Arch::Arm,
        options: opts,
    }
}
