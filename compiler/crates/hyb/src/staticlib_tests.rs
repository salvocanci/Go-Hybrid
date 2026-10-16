use super::lib_arch_matches;
use std::sync::atomic::{AtomicUsize, Ordering};

fn probe(bytes: &[u8]) -> bool {
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let path = std::env::temp_dir().join(format!(
        "hyb-macho-{}-{}.a",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::write(&path, bytes).unwrap();
    let result = lib_arch_matches(&path);
    std::fs::remove_file(path).unwrap();
    result
}

fn macho(cpu: u32, big_endian: bool) -> Vec<u8> {
    // mach_header_64: MH_MAGIC_64, cputype, cpusubtype, MH_OBJECT,
    // ncmds, sizeofcmds, flags, reserved.
    [0xfeedfacf_u32, cpu, 0, 1, 0, 0, 0, 0]
        .into_iter()
        .flat_map(|n| {
            if big_endian {
                n.to_be_bytes()
            } else {
                n.to_le_bytes()
            }
        })
        .collect()
}

fn host_cpu() -> u32 {
    match std::env::consts::ARCH {
        "x86_64" => 0x01000007,
        "aarch64" => 0x0100000c,
        other => panic!("unsupported test host {other}"),
    }
}

fn member(name: &str, data: &[u8]) -> Vec<u8> {
    assert!(name.len() <= 16);
    let mut out = format!(
        "{name:<16}{:<12}{:<6}{:<6}{:<8}{:<10}`\n",
        0,
        0,
        0,
        0,
        data.len()
    )
    .into_bytes();
    assert_eq!(out.len(), 60);
    out.extend_from_slice(data);
    if !data.len().is_multiple_of(2) {
        out.push(b'\n');
    }
    out
}

fn bsd_member(name: &[u8], data: &[u8]) -> Vec<u8> {
    let mut payload = name.to_vec();
    payload.extend_from_slice(data);
    member(&format!("#1/{}", name.len()), &payload)
}

fn archive(members: &[Vec<u8>]) -> Vec<u8> {
    let mut out = b"!<arch>\n".to_vec();
    for m in members {
        out.extend_from_slice(m);
    }
    out
}

#[test]
fn macho_raw_and_short_archive_members_match_only_host_arch() {
    for cpu in [0x01000007, 0x0100000c, 7, 12, 0x01000012] {
        for big in [false, true] {
            let obj = macho(cpu, big);
            assert_eq!(probe(&obj), cpu == host_cpu(), "raw cpu={cpu:x} big={big}");
            assert_eq!(
                probe(&archive(&[member("hyrt.o/", &obj)])),
                cpu == host_cpu()
            );
        }
    }
}

#[test]
fn macho_bsd_names_and_extended_symbol_tables() {
    // LLVM/Darwin archives put NUL-padded names in the member payload,
    // including __.SYMDEF. Sizes include the name, and odd members are padded.
    let obj = macho(host_cpu(), false);
    for symbol in [b"__.SYMDEF\0\0\0".as_slice(), b"__.SYMDEF SORTED\0"] {
        assert!(probe(&archive(&[
            bsd_member(symbol, &[0; 131_073]),
            bsd_member(b"hyrt.long.rcgu.o\0\0\0", &obj),
        ])));
    }
    assert!(probe(&archive(&[
        member("/", &[0; 3]),
        member("//", b"long-name-table"),
        member("__.SYMDEF/", &[0; 4]),
        bsd_member(b"odd.o", &obj),
    ])));
    let foreign = if host_cpu() == 0x01000007 {
        0x0100000c
    } else {
        0x01000007
    };
    assert!(!probe(&archive(&[bsd_member(
        b"foreign.o",
        &macho(foreign, false)
    )])));
}

#[test]
fn macho_invalid_headers_and_archive_names_fail_closed() {
    let obj = macho(host_cpu(), false);
    for n in 0..32 {
        assert!(!probe(&obj[..n]), "truncated at {n}");
    }
    let mut executable = obj.clone();
    executable[12] = 2; // MH_EXECUTE, not an object file
    assert!(!probe(&executable));
    let mut fat = obj.clone();
    fat[..4].copy_from_slice(&[0xca, 0xfe, 0xba, 0xbe]);
    assert!(!probe(&fat));
    for name in ["#1/", "#1/no", "#1/0", "#1/999999999999"] {
        assert!(!probe(&archive(&[member(name, &obj)])), "bad name {name}");
    }
    let valid = archive(&[bsd_member(b"hyrt.o", &obj)]);
    assert!(!probe(&valid[..valid.len() - 1]), "member exceeds file");
}

#[test]
fn archive_object_probe_cannot_read_into_next_member() {
    // A 4-byte first member must not borrow the next ar header's bytes to
    // look like a 20-byte ELF/COFF object. The old reader did exactly that.
    let coff = if host_cpu() == 0x01000007 {
        [0x64, 0x86, 0, 0]
    } else {
        [0x64, 0xaa, 0, 0]
    };
    assert!(!probe(&archive(&[
        member("short.o/", &coff),
        member("next.o/", &[0; 32])
    ])));
    assert!(!probe(&archive(&[
        bsd_member(b"short.o", &macho(host_cpu(), false)[..20]),
        member("next.o/", &[0; 32])
    ])));
}
