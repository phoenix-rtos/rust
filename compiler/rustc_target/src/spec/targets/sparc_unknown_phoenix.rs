use rustc_abi::Endian;

use crate::spec::{Arch, Target, TargetMetadata, base};

pub(crate) fn target() -> Target {
    let mut opts = base::phoenix::opts();
    opts.linker = Some("sparc-phoenix-gcc".into());
    opts.endian = Endian::Big;
    opts.cpu = "leon3".into();
    opts.features = "+leoncasa".into();
    opts.max_atomic_width = Some(32);
    opts.atomic_cas = true;

    Target {
        llvm_target: "sparc-unknown-phoenix".into(),
        metadata: TargetMetadata {
            description: Some("32-bit SPARC V8 LEON Phoenix-RTOS".into()),
            tier: Some(3),
            host_tools: Some(false),
            std: Some(true),
        },
        pointer_width: 32,
        data_layout: "E-m:e-p:32:32-i64:64-i128:128-f128:64-n32-S64".into(),
        arch: Arch::Sparc,
        options: opts,
    }
}
