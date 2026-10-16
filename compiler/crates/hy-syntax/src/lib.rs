//! hy-syntax — lexer, parser, and AST for the Hybrid language.
//!
//! Public API (the walking-skeleton surface):
//!   * `parse_file(path, src) -> Result<File, Vec<Diagnostic>>`
//!   * `dump_ast(&File) -> String` (debug facility for the checker/emitter)
//!   * `File`, `Decl`, `Stmt`, `Expr`, `TypeExpr`, ... (re-exported from ast)
//!   * `lex(path, src)` + `Token`/`Tok` (re-exported from lexer — used by
//!     parser unit tests and handy for tooling)
//!
//! Implementation status:
//!   * `ast` — the contract (complete; owned by the lead)
//!   * `lexer` / `parser` — implemented (agent 5-b). All 20 checker-corpus
//!     programs, all 10 spike-6 programs, and ALL existing example programs
//!     (01–03 must-parse; 04–09 stretch, incl. select/match/generics) parse;
//!     see tests/parse_all.rs. Contract gaps (surface the AST cannot express)
//!     are documented in parser.rs module docs and the agent's report.
//!   * Parse errors are `HYB-E0002` (parse-error slot, not yet in the
//!     registry — passes through with no fix-its); `HYB-E0001` stays with
//!     the lexer's LX2 identifier-case violations, per the registry table.

mod ast;
mod lexer;
mod parser;

pub use ast::*;
pub use lexer::{lex, Tok, Token};
pub use parser::{dump_ast, parse_file};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_file_ok_and_err_paths() {
        let ok = parse_file("t.hy", "fn main() { x := 1 }");
        assert!(ok.is_ok());
        let file = ok.unwrap();
        assert_eq!(file.path, "t.hy");
        assert_eq!(file.decls.len(), 1);

        let err = parse_file("t.hy", "fn main() { x := }");
        assert!(err.is_err());
        let diags = err.unwrap_err();
        assert_eq!(diags.len(), 1);
        assert_eq!(diags[0].code, "HYB-E0002");
        assert_eq!(diags[0].file, "t.hy");
        assert!(diags[0].message.contains("line") || diags[0].span.start.line >= 1);
    }

    #[test]
    fn dump_ast_is_debug_text() {
        let file = parse_file("t.hy", "fn main() { }").unwrap();
        let s = dump_ast(&file);
        assert!(s.contains("File"));
        assert!(s.contains("FnDecl"));
    }
}
