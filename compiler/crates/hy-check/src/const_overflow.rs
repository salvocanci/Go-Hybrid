//! const_overflow.rs — constant initializers that overflow a declared
//! fixed-width integer type (issue #148).
//!
//! `var n int8 = 300` (and the file-level `const` twin) pass `hyb check`
//! with 0 diagnostics today, then fail `go vet` / `go build` with
//! `cannot use 300 as int8 value (overflows)`. The accepted-should-
//! emit-buildable-Go contract requires a checker diagnostic (HYB-E6002)
//! for that narrow constant case. Non-constant operands stay out of
//! scope — Go truncates at run time via an explicit conversion
//! (SPEC-LANGUAGE X4), and the conversion form `int8(x)` is unaffected.

use crate::model::{unwrap_parens, Checker};
use hy_diag::{Diagnostic, Span};
use hy_syntax::{Expr, LitKind, TypeExpr, UnOp};

impl<'a> Checker<'a> {
    /// When `ty` is a fixed-width integer and `value` is an integer
    /// constant outside that type's range, emit HYB-E6002.
    pub(crate) fn check_const_overflow_init(&mut self, name: &str, ty: &TypeExpr, value: &Expr) {
        let TypeExpr::Named {
            name: ty_name,
            span: ty_span,
        } = ty
        else {
            return;
        };
        let Some((lo, hi)) = fixed_width_int_range(ty_name) else {
            return;
        };
        let Some(v) = const_int_value(value) else {
            return;
        };
        if v >= lo && v <= hi {
            return;
        }
        let span = value.span();
        let msg = format!(
            "constant `{}` overflows declared type `{}` of `{}` (HYB-E6002)",
            value.render(),
            ty_name,
            name
        );
        let notes = vec![
            format!(
                "why: Go rejects a constant initializer outside `{}`'s range (`cannot use … as {} value (overflows)`), so an accepted Hybrid program would emit unbuildable Go (issue #148)",
                ty_name, ty_name
            ),
            format!(
                "fix: use a constant in [{}, {}], widen the declared type, or convert from a variable if truncation is intentional (`x := {}; y := {}(x)`)",
                lo, hi, value.render(), ty_name
            ),
            format!(
                "note: the declared type was written here ({})",
                span_hint(*ty_span)
            ),
        ];
        self.diags.push(
            Diagnostic::error("HYB-E6002", self.path.clone(), span, msg).with_notes(notes),
        );
    }
}

fn span_hint(span: Span) -> String {
    format!("{}:{}", span.start.line, span.start.col)
}

/// Inclusive representable range for a Hybrid fixed-width integer type
/// name (SPEC-LANGUAGE §11 / Go's typed-constant assignment rule).
/// Platform-word `int`/`uint`/`isize`/`usize` use the 64-bit LP64 ranges
/// the emitter targets (SPEC B9 / X7).
fn fixed_width_int_range(name: &str) -> Option<(i128, i128)> {
    Some(match name {
        "i8" | "int8" => (i8::MIN as i128, i8::MAX as i128),
        "u8" | "uint8" | "byte" => (0, u8::MAX as i128),
        "i16" | "int16" => (i16::MIN as i128, i16::MAX as i128),
        "u16" | "uint16" => (0, u16::MAX as i128),
        "i32" | "int32" | "rune" => (i32::MIN as i128, i32::MAX as i128),
        "u32" | "uint32" => (0, u32::MAX as i128),
        "i64" | "int64" | "int" | "isize" => (i64::MIN as i128, i64::MAX as i128),
        "u64" | "uint64" | "uint" | "usize" | "uintptr" => (0, u64::MAX as i128),
        _ => return None,
    })
}

/// Evaluate a pure integer constant expression the checker can see without
/// a full constant folder: int literals (any base the lexer keeps),
/// unary `-`, and parentheses. Anything else (idents, calls, binary ops)
/// is out of scope for HYB-E6002.
fn const_int_value(e: &Expr) -> Option<i128> {
    match unwrap_parens(e) {
        Expr::Lit {
            kind: LitKind::Int(s),
            ..
        } => parse_int_lit(s),
        Expr::Unary {
            op: UnOp::Neg,
            operand,
            ..
        } => {
            let v = const_int_value(operand)?;
            v.checked_neg()
        }
        _ => None,
    }
}

fn parse_int_lit(s: &str) -> Option<i128> {
    let s = s.as_bytes();
    if s.is_empty() {
        return None;
    }
    if s.len() >= 2 && s[0] == b'0' {
        match s[1].to_ascii_lowercase() {
            b'x' => return i128::from_str_radix(std::str::from_utf8(&s[2..]).ok()?, 16).ok(),
            b'b' => return i128::from_str_radix(std::str::from_utf8(&s[2..]).ok()?, 2).ok(),
            b'o' => return i128::from_str_radix(std::str::from_utf8(&s[2..]).ok()?, 8).ok(),
            _ => {}
        }
    }
    i128::from_str_radix(std::str::from_utf8(s).ok()?, 10).ok()
}

#[cfg(test)]
mod unit {
    use super::*;

    #[test]
    fn ranges_match_go_fixed_width() {
        assert_eq!(fixed_width_int_range("int8"), Some((-128, 127)));
        assert_eq!(fixed_width_int_range("byte"), Some((0, 255)));
        assert_eq!(fixed_width_int_range("u16"), Some((0, 65535)));
        assert!(fixed_width_int_range("string").is_none());
        assert!(fixed_width_int_range("float64").is_none());
    }

    #[test]
    fn parse_bases() {
        assert_eq!(parse_int_lit("300"), Some(300));
        assert_eq!(parse_int_lit("0x12C"), Some(300));
        assert_eq!(parse_int_lit("0b101"), Some(5));
        assert_eq!(parse_int_lit("0o10"), Some(8));
    }
}
