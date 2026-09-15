use crate::spec::{Arch, Cc, LinkerFlavor, Lld, StackProbeType, Target, TargetMetadata, base};

pub(crate) fn target() -> Target {
    let mut opts = base::phoenix::opts();
    opts.cpu = "pentium".into();
    opts.linker = Some("i386-pc-phoenix-gcc".into());
    opts.max_atomic_width = Some(64);
    opts.plt_by_default = false;
    opts.stack_probes = StackProbeType::Call;
    opts.add_pre_link_args(LinkerFlavor::Gnu(Cc::Yes, Lld::No), &["-m32"]);

    Target {
        llvm_target: "i586-unknown-phoenix".into(),
        metadata: TargetMetadata {
            description: Some("32-bit x86 Phoenix-RTOS".into()),
            tier: Some(3),
            host_tools: Some(false),
            std: Some(true),
        },
        pointer_width: 32,
        data_layout:
            "e-m:e-p:32:32-p270:32:32-p271:32:32-p272:64:64-i128:128-f64:32:64-f80:32-n8:16:32-S128"
                .into(),
        arch: Arch::X86,
        options: opts,
    }
}
