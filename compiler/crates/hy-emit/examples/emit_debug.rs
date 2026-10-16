use hy_emit::emit_go;
use hy_syntax::parse_file;

fn show(label: &str, src: &str) {
    match parse_file("t.hy", src) {
        Ok(f) => match emit_go(&f) {
            Ok(go) => println!("=== {} ===\n{}\n", label, go),
            Err(e) => println!("=== {} (emit err) ===\n{}\n", label, e.message),
        },
        Err(d) => println!("=== {} (parse err) ===\n{:?}\n", label, d),
    }
}

fn main() {
    show(
        "if-chain",
        "fn main() {\n    if a {\n    } else if b {\n    } else {\n    }\n}\n",
    );
    show("plain-main", "fn main() {\n    fmt.println(\"x\")\n}\n");
    show("named-results", "fn f() (code int) {\n    return 3\n}\n");
    show(
        "method",
        "struct g {\n    n int\n}\n\nfn (p *g) add(x int) {\n    p.n += x\n}\n",
    );
    show(
        "example03",
        &std::fs::read_to_string("/home/z/go-hybrid/examples/03-worker-pool/program.hy").unwrap(),
    );
}
