use crate::spec::{Arch, CfgAbi, FloatAbi, Target, TargetMetadata, base};

pub(crate) fn target() -> Target {
    let mut opts = base::phoenix::opts();
    opts.linker = Some("arm-phoenix-gcc".into());
    opts.cfg_abi = CfgAbi::EabiHf;
    opts.llvm_floatabi = Some(FloatAbi::Hard);
    opts.features = "+v7,+thumb2,+thumb-mode,+vfp3,+neon,+strict-align,+read-tp-tpidruro".into();
    opts.max_atomic_width = Some(64);
    opts.c_enum_min_bits = Some(8);

    Target {
        llvm_target: "armv7a-unknown-phoenix-eabihf".into(),
        metadata: TargetMetadata {
            description: Some("ARMv7-A Cortex-A Phoenix-RTOS (hard float)".into()),
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
