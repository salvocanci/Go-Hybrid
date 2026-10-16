# How top repos write READMEs — study for Go-Hybrid

Task ID 4-d · research-readme-study · 2025
Purpose: distill how the best open-source repos structure their READMEs so Go-Hybrid's
public README.md (currently a bare `# Go-Hybrid`) can be written at that standard.

Method: fetched and read the actual READMEs of 15 top repos (raw.githubusercontent /
Codeberg), plus GitHub API metadata for stars and default branches. Line numbers cited
below (≈ L42) refer to the fetched README copies as of this study.

## Corpus

| Repo | Stars (approx) | Category | README lines | Hero pattern | Badges used |
|---|---|---|---|---|---|
| rust-lang/rust | ~119.7k | language | 79 | centered `<picture>` logo w/ dark+light variants; nav row of 5 links; no H1 text | none |
| golang/go | ~139.2k | language | 42 | H1, one-sentence pitch, gopher image w/ credit | none |
| ziglang/zig (Codeberg) | ~43.3k | language | 815 | logo + tagline; no code, no badges; 90% build instructions | none |
| tinygo-org/tinygo | ~17.8k | compiler for a language | 159 | H1 "TinyGo – Go compiler for small places"; 5 per-platform CI badges | 5 CI (linux/macOS/win/docker/nix) |
| oven-sh/bun | ~96.2k | runtime/toolchain | 446 | centered logo, H1, badge row (incl. joke "speed: fast"), nav row w/ `•` | discord, stars, speed(joke) |
| denoland/deno | ~108.8k | runtime | 116 | H1, social badges, right-aligned mascot, pronunciation guide | crates.io + 4 social |
| tokio-rs/tokio | ~33.4k | Rust flagship lib | 261 | H1, pitch + 3 bullets, 4 badges, nav row | crates, MIT, CI, discord |
| tauri-apps/tauri | ~111.8k | Rust flagship framework | 96 | splash image; 9 badges | status, license, test, FOSSA, discord, website, sponsor |
| rust-lang/rust-analyzer | ~16.9k | tooling flagship | 66 | centered SVG logo; codecov badge mid-file | codecov only |
| bytecodealliance/wasmtime | ~18.7k | runtime flagship | 184 | centered div: H1 `<code>` name, bold one-liner, "A Bytecode Alliance project", badges, H3 nav | CI, zulip, rustc-stable, docs.rs |
| dtolnay/cxx | ~6.8k | interop (closest to us) | 387 | setext title + pitch; 4 `for-the-badge` badges | github, crates.io, docs.rs, CI |
| ihciah/rust2go | ~0.4k | interop (closest to us) | 153 | H1, 2 badges, one-para pitch | crates.io, codecov |
| sharkdp/bat | ~51k | polished tool | 941 | centered logo w/ tagline baked in; badges; anchor mini-TOC + 5 translations | CI, license, crates |
| BurntSushi/ripgrep | ~69.0k | polished tool | 541 | setext title, plain prose pitch, screenshot | CI, crates, packaging |
| junegunn/fzf | ~83.6k | polished tool | 1153 | centered logo + badges; Highlights 4-bullet block; 100+ item TOC | CI, version, license, contributors, sponsors, stars |

Two structural outliers worth naming: **rust-lang/rust** (79 lines) and **golang/go**
(42 lines) — huge projects with tiny READMEs, because the marketing/pitching lives on
their dedicated websites (rust-lang.org, go.dev). A new unknown project cannot afford
this; **ziglang/zig's** 815-line README with zero code samples is an anti-pattern for
any project that doesn't already have a famous site.

## The recurring anatomy

Ordered skeleton that appears (with variations) across the corpus:

1. **Identity block** — logo or wordmark, project name, one-line tagline. Often
   centered (`<div align="center">` / `<p align="center">`): rust L1-11, bun L1-4,
   wasmtime L1-27, bat L1-7, fzf L1-9.
2. **Trust strip** — badges immediately under identity (tokio L15-18, tauri L3-10,
   cxx L4-7). Languages proper (rust, go, zig) skip badges entirely.
3. **Nav row** — 3-6 pipe- or bullet-separated links: Website | Docs | Chat |
   Contributing (rust L10, tokio L29-32, wasmtime L18-26, bun L12-21, bat L9-20).
4. **One-paragraph pitch** — what it is, for whom, built on what (deno L9-16, cxx
   L9-17, bun L25-35).
5. **"Why X" / features** — 3-5 bullets, bolded keyword + one sentence (rust "Why
   Rust?" L22-28: Performance/Reliability/Productivity; tokio L6-13:
   Fast/Reliable/Scalable; wasmtime L89-121: Fast/Secure/Configurable/WASI/Standards).
6. **Code sample / demo above the fold** — code for libraries/languages (tokio L51-98,
   cxx L71-117, tinygo L12-35), screenshot/GIF for CLI tools (bat L22-52, fzf L30,
   ripgrep L34-36).
7. **Installation / quick start** — copy-pasteable, multi-platform (deno L18-60,
   bun L44-69, wasmtime L29-45). tinygo inverts the order: examples FIRST, install
   after (L12-74).
8. **"Your first program"** — languages/runtimes show a first program + the command
   to run it + what success looks like (deno L67-89 "This should start a local web
   server on http://localhost:8000").
9. **Deeper material** — design overview, comparison, platform support, toolchain
   requirements, architecture links (tauri ARCHITECTURE.md L18, cxx "Details" L144+,
   rust2go "Key Design" L71+).
10. **Community/help** — Getting Help with a triage order: docs first, then chat
    (tokio L109-120; rust-analyzer splits by intent L44-52).
11. **Contributing** — always links a CONTRIBUTING.md rather than inlining rules
    (rust L51-55, deno L102-105, tokio L122-128).
12. **License** — last; dual MIT/Apache formula with the contribution clause (cxx
    L374-387, tokio L251-261, bat L936-941).

Variations: mature tools grow a full TOC (fzf, bat) or become manuals (fzf 1153
lines); flagship libs keep ~250 lines and push detail to books/guides (tokio);
languages keep <100 lines and delegate to their site (rust, go).

## Hero/pitch patterns

The one-liners, and the formula behind them:

- Rust (in logo alt-text, L5): "A language empowering everyone to build reliable and
  efficient software."
- Go (L3-4): "makes it easy to build simple, reliable, and efficient software."
- Zig (L3-4): "for maintaining **robust**, **optimal**, and **reusable** software."
- Tokio (L3-4): "A runtime for writing reliable, asynchronous, and slim applications
  with the Rust programming language."
- TinyGo (L5): "a Go compiler intended for use in small places such as
  microcontrollers, WebAssembly (wasi), and command-line tools."
- CXX (L1): "safe FFI between Rust and C++" — safety claim + both audiences in 6 words.
- Bun (L27-29): "an all-in-one toolkit for JavaScript and TypeScript apps… a drop-in
  replacement for Node.js."
- bat (L6): "A *cat(1)* clone with syntax highlighting and Git integration." — the
  "X clone with Y" formula: instant mental model via a known tool.
- wasmtime (L5-6): "A standalone runtime for WebAssembly" + org attribution.
- rust2go (L6): "a simple and efficient way to call Golang from Rust with native
  async support."

**The formula:** `[Name] is a [category noun] for [audience/context] that
[differentiator]`, carrying 2-3 adjectives that ARE the value proposition
(reliable/efficient, robust/optimal/reusable, simple/reliable/efficient). The
adjectives are claims the rest of the README must substantiate. For interop tools,
naming BOTH audiences in the first line is the pattern (cxx, rust2go). Positioning by
analogy ("drop-in replacement", "X clone with") buys instant comprehension but must
be literally true.

## Badge strategy

What earns trust vs noise:

- **Trust-earning:** CI/build status (tokio L17, cxx L7, tinygo's 5 per-platform
  badges L3), license (bat L4), crates.io version for installable libs (cxx L5),
  docs.rs (wasmtime L15), and **status** — tauri ships a plain
  `status-stable-blue` badge (L3), a pattern perfect for pre-1.0 projects to invert
  to `status-experimental`.
- **Noise:** social-follow badges (deno has 4; they market, they don't inform),
  stars badge (bun, fzf — vanity), joke badges (bun's "speed: fast" L9 — works only
  with 96k stars of goodwill).
- **v0 project should claim:** license badge, CI badge (once CI exists and is
  green), a `status: experimental / pre-MVP` badge. **Should NOT claim:** version
  (no releases yet), coverage (no meaningful corpus yet), chat/discord (doesn't
  exist), downloads/stars (zero — a 0 visible to everyone undermines credibility).
  Badges must be live-generated; a stale red CI badge is worse than none.

## Quick-start patterns

Two schools:

- **Install-first:** deno/bun/wasmtime — multi-platform one-liners (curl script,
  brew, choco, winget) before any code. Works because the artifact is installable
  today.
- **Code-first:** tinygo shows a blinking-LED program (L14-35) BEFORE installation;
  cxx shows `Cargo.toml` deps at L19-25 before any prose about building; tokio opens
  its Example section with the exact `tokio = { version = "...", features = ["full"] }`
  line (L57-60) so the snippet is actually runnable.
- **Show what success looks like:** wasmtime ends its quick start with the literal
  output block `Hello, world!` (L76-80); deno says the server appears at
  localhost:8000 (L85-86). This is cheap and converts a skim into a mental "I could
  do this."
- **Playground links** lower friction: ripgrep links an unofficial playground +
  interactive tutorial (L223-230). A language too new to install benefits from any
  "try it" substitute, even a GIF/asciinema.

For Go-Hybrid (pre-MVP): the honest quick start is build-from-source or "watch this
repo" — so the code-first school is mandatory, and the code sample itself becomes the
product demo.

## Code-sample strategy for languages

- **Mature languages show no code in the README** (rust, go, zig: zero samples).
  Their pitch is carried by the website and by fame. **New compilers/runtimes always
  show code on the first screen:** tinygo (Go blinky at L16), bun (`bun run
  index.tsx` at L31-33), deno (3-line `Deno.serve` at L73-77).
- The first sample must show **the unique value, not hello-world**: tinygo's blinky
  demonstrates "Go on a microcontroller" (the whole pitch); deno's server shows
  TypeScript-running-as-is; bun's shows zero-config TS/JSX.
- Samples are **complete and runnable**: tokio's echo server compiles as-is (L63-98);
  cxx's bridge example is annotated line-by-line with comments explaining each block
  (L82-116) AND is backed by a `demo/` directory: "A runnable version of this
  example is provided under the demo directory… run `cargo run`" (L79-80), with
  links to every involved file (L123-128).
- **Annotation style:** cxx comments the *interesting* lines only ("Shared structs,
  whose fields will be visible to both languages", L85) — comments teach the
  boundary model while you read the code. This is the strongest single pattern in
  the corpus for an interop project.
- Scale ladder: one hero sample inline → `examples/` directory link ("More examples
  can be found here", tokio L100-104) → a "real world" reference app (tokio's
  mini-redis, L100-101).

## Status/roadmap honesty patterns

How pre-1.0 projects set expectations (this is our exact situation):

- **cxx, "Remaining work" (L358-366):** "This is still early days for CXX; I am
  releasing it as a minimum viable product to collect feedback on the direction and
  invite collaborators." — names the stage, states the purpose of publishing, invites
  specific help ("report issues if you run into trouble building").
- **tauri:** a `status-stable-blue` badge (L3) — status is a first-class, glanceable
  signal, not buried prose.
- **rust2go:** a Milestones section of checkbox groups, ALL checked, ending with an
  "Engineering & Maintainability" group (L106-145) — shows completed work honestly
  rather than promising futures.
- **bun:** links a public roadmap issue right in the nav row (L19: Roadmap →
  issues/159).
- **tinygo:** routes "what exactly is supported?" to a dedicated lang-support page
  (L102-104) instead of vaguely claiming compatibility.
- **ripgrep's "Why shouldn't I use ripgrep?" (L161-180):** enumerates the cases where
  you should NOT use it, including "not ubiquitous, does not conform to POSIX… the
  best tool for this job is good old grep." Radical honesty that builds more trust
  than any claim.
- **cxx's honest caveat in the pitch itself (L13-17):** immediately after the safety
  claim: "This doesn't change the fact that 100% of C++ code is unsafe." The pitch
  survives because the *precise* claim is scoped ("auditing just the C++ side would
  be sufficient").
- **tokio's MSRV + release schedule sections (L176-237):** explicit support policy —
  appropriate at scale; for us the analog is a "supported crates / supported
  platforms" scope table.

## Comparison-table patterns

Positioning vs alternatives without FUD:

- **cxx "Comparison vs bindgen and cbindgen" (L181-218):** concedes its OWN
  weakness first ("there is repetition of all the function signatures"), reframes by
  role ("CXX fills a somewhat different role"), then explicitly blesses mixing both
  tools ("It would also be reasonable to mix and match"). No competitor is called
  bad; the differentiator (safe end-to-end vs unsafe all the way through, L202-211)
  does the work.
- **bat "Project goals and alternatives" (L924-934):** 4 goal bullets, then "There
  are a lot of alternatives… See this document for a comparison" — defers detail to
  a separate doc, keeps the README clean.
- **ripgrep:** links a THIRD-PARTY comparison table (written by ack's author, L213-215)
  — citing your competitor's own comparison is the strongest no-FUD move available —
  and discloses what that table misses.
- **Benchmarks with caveats (ripgrep L39-114):** every table states hardware, corpus,
  flags "to ensure they are doing equivalent work", plus "a single benchmark is
  never enough" (L47-49) and a "Beware of performance cliffs" table showing ripgrep
  LOSING or barely winning (L87-103). Benchmark honesty = ratios + reproducible
  commands in the table itself.
- **Wasmtime splits lists by ownership:** "Languages supported by the Bytecode
  Alliance" vs "by the community" (L139-151) — clarity about what is first-party.
- Bun's analogy positioning ("drop-in replacement for Node.js") and cxx's
  role-positioning show two safe framings; attack-ads framing appears nowhere in the
  corpus.

## Navigation/TOC/linking patterns

- **Mini anchor nav near the top** for medium READMEs: bat's 5-link bullet row
  (L9-14); ripgrep's "Documentation quick links" (L22-31) which mixes anchors and
  external docs.
- **Full TOC only when the README is a manual** (fzf L45-106, generated via
  vim-markdown-toc). bun instead ships a nested "Quick links" doc-sitemap (L87-220).
- **Piped nav row in the hero** for short READMEs (rust, tokio, wasmtime, bun).
- **Reference-style links** keep prose clean: rust defines all URLs at section
  bottom (L16-20); tokio and deno do the same. GitHub auto-renders them.
- **Deep links over vague ones:** "See the docs" loses to wasmtime's "📚 Read the
  Wasmtime guide here! 📚" (L172) with a sentence on what the guide answers.
- **Docs split by reader intent:** rust-analyzer separates "If you want to
  **contribute**…" from "If you want to **use**…" (L29-37). Tokio's Getting Help
  gives an ordered triage: guides → API docs → Discord → discussions (L109-120).
- Reference-style link definitions + anchor links + intent-split docs = the reader
  never dead-ends.

## Anti-patterns observed (what top repos avoid)

1. **Walls of text with no code** — Zig's README (815 lines, zero samples) only survives because ziglang.org exists; fatal for an unknown project.
2. **Over-claiming** — every strong claim is scoped (cxx scopes its safety claim within 4 lines of making it, L9-17); nobody says "blazing fast" without a table, hardware, and a caveat (ripgrep is the model).
3. **Stale/no-value badges** — social and vanity badges (deno, bun, fzf) add nothing for a new reader; a red CI badge actively harms; rust/go/zig ship zero badges and lose nothing.
4. **README-as-manual bloat** — fzf (1153 lines) and bat (941) work at 50k+ stars; the pattern to copy is tokio (261) or wasmtime (184): depth lives in linked guides.
5. **TODO sections / empty promises** — rust2go's milestones work because every box is checked; unchecked boxes must be labeled roadmap, not features. No top README ships a bare "TODO: add examples".
6. **Inlining contributing rules** — everyone links CONTRIBUTING.md instead (rust L51-55, deno L102-105).
7. **Unlabeled aspirational code** — no top repo shows code that doesn't run; a pre-MVP language MUST label mockup samples explicitly (see skeleton §4).
8. **Monetization above the pitch** — fzf's merch banner (L13-24) precedes the description; tolerable only at 83k stars.
9. **Burying the status** — pre-1.0-ness must be glanceable (badge/banner), not found in paragraph nine; and **FUD comparisons** appear nowhere in the corpus, even between direct competitors (cxx vs bindgen is gracious throughout).

## RECOMMENDED SKELETON for Go-Hybrid's README.md

Tailored to: new language, pre-MVP, Go+Rust audience, public repo
(limitlessprojects/Go-Hybrid), one-command-build pitch. Annotated section by section.

```markdown
<div align="center">
  # Hybrid            (wordmark; text is fine — rust-analyzer shipped an SVG, bat baked
                       the tagline INTO the logo; both fine at our stage)
  Rust-grade memory safety for Go-shaped code.
  (one-line tagline; see hero options below)

  [status: experimental] [license: MIT OR Apache-2.0] [CI: …]   ← only badges that are
                                                                 true and live
  Docs | Spec | Roadmap | Examples | Contributing     ← piped nav row (rust/tokio style)
</div>

1. STATUS BANNER (immediately below hero — glanceable honesty, cxx "Remaining work" +
   tauri status-badge patterns):
   > Hybrid is pre-MVP and in active research/spike phase. Nothing is installable
   > yet. This README describes the target design; items marked ✅ in Roadmap are
   > implemented and tested. Watch releases or read PLAN.md for live status.

2. WHAT IT IS (one paragraph, deno/cxx style, naming BOTH audiences like cxx):
   Hybrid is a programming language for teams with an existing Go codebase who want
   Rust-grade memory safety — incrementally, file by file, without a rewrite. Write
   `.hy` files beside your `.go` files, call pinned Rust crates from Hybrid code,
   and produce a working binary with ONE command: `hybrid build`.

3. WHY HYBRID (3-4 bold bullets, one sentence each — rust "Why Rust?" / tokio style):
   - **Safe by default:** no data races, no use-after-free in Hybrid's safe mode;
     safety claims are backed by compile-fail tests, not assertions.
   - **Incremental:** adopt per-file inside an existing Go module. No rewrite.
   - **One build command:** `hybrid build` drives the Go and Rust toolchains; you
     never run two build systems by hand.
   - **Rust crates, Go ergonomics:** error handling, concurrency and generics feel
     like Go; the crate ecosystem is Rust's.

4. FIRST-SCREEN CODE SAMPLE (the product demo — tinygo/bun/deno pattern; MUST be
   clearly labeled as target syntax while pre-MVP, because no top repo shows
   non-running code unlabeled):

   ```hy
   // checkout.hy — Go-shaped syntax, Rust-grade safety
   import "rust/regex"

   fn validate_email(raw string) (string, error) {
       re := regex.must_compile(`^[\w.+-]+@[\w-]+\.[\w.]+$`)
       if !re.is_match(raw) {
           return "", errors.new("invalid email")
       }
       return raw, nil
   }
   ```
   ```go
   // main.go — your existing Go code, unchanged
   email, err := hybrid.ValidateEmail(raw)
   ```
   ```sh
   hybrid build && ./myapp     # one command, both toolchains
   ```
   (Target syntax mockup — v0.x; see Status. — this label is REQUIRED until a
   compiler can actually run this example end to end.)

5. HOW IT WORKS (3-5 bullets + link to SPEC.md — tauri links ARCHITECTURE.md at
   L18; cxx "Overview" L39-67): `.hy` compiles to Rust → boundary rules (no
   unwinding across, no cross-allocator frees, no raw cross-language pointers in
   safe mode) → `hybrid build` orchestrates cargo + go build → single binary.

6. ROADMAP / STATUS (rust2go milestones pattern: grouped checkboxes, checked =
   done+tested; plus tinygo's "route to a support page" honesty):
   - [x] Repo scaffold, toolchains pinned (done)
   - [ ] Spike: FFI boundary overhead (in progress)
   - [ ] MVP-0 walking skeleton: one .hy file callable from Go
   Link: PLAN.md (live status), STATUS.md.

7. WHY NOT X (fair comparison, cxx/ripgrep pattern — concede first, differentiate by
   role, zero FUD; include a "When you should NOT use Hybrid" block after
   ripgrep's "Why shouldn't I use ripgrep?"):
   - vs staying in Go: Go is excellent; Hybrid is for the safety-critical slices.
   - vs rewriting in Rust: full rewrites rarely ship; Hybrid is the incremental path.
   - vs CGo/FFI today: works today, but you hand-audit unsafe boundaries and run two
     build systems; Hybrid's bet is checked boundaries + one command.
   - When NOT to use Hybrid: you need arbitrary existing Go code unmodified, every
     Rust crate, or a 1.0 stability contract. Those are explicit non-goals.

8. GET IT (honest install section — pre-MVP version of deno's install block):
   Not installable yet. Track releases, or build from source after MVP-0 lands
   (link to BUILD.md when it exists).

9. LEARN MORE (intent-split, rust-analyzer pattern: "if you want to USE…" vs "if you
   want to CONTRIBUTE…"): SPEC.md (design), research/ (spike evidence), examples/
   (once MVP-0 exists).

10. GETTING HELP / CONTRIBUTING (link out, never inline rules — universal corpus
    pattern): CONTRIBUTING.md, GitHub Discussions/issues.

11. LICENSE (last, dual-license formula verbatim from cxx L374-387: "Licensed under
    either of Apache-2.0 or MIT at your option… any contribution … shall be dual
    licensed as above" — matches the LICENSE-MIT/LICENSE-APACHE files already in repo).
```

**Hero text options** (formula applied: category noun + audience + differentiator,
adjectives are the value prop):

- A (mission-shaped, Rust-style): "A language that lets Go teams build reliable
  software with Rust-grade memory safety — one file at a time."
- B (two-audience interop style, cxx-style): "Hybrid — Rust-grade memory safety for
  existing Go codebases, without the rewrite."
- C (tagline-short, Zig-style): "Rust-grade safety. Go-shaped code. One build
  command."
- D (analogy, bat-style — riskiest, only if literally true at MVP): "Go with a
  borrow checker."

Recommendation: B as the one-line pitch under the wordmark + C as the tagline inside
the identity block. B names both audiences (Go teams / Rust safety) like cxx names
Rust and C++; C carries the three concrete promises the README then substantiates
(safety → Why Hybrid; Go-shaped → code sample; one build → quick start).

Line-count target for the final README: **120-180 rendered lines** — wasmtime (184)
and tokio (261) are the right size class; depth lives in SPEC.md/PLAN.md/docs, not
the README.

## Sources

Fetched and read in full during this study (raw copies in agent workspace):

- rust-lang/rust — https://raw.githubusercontent.com/rust-lang/rust/master/README.md (79 lines)
- golang/go — https://raw.githubusercontent.com/golang/go/master/README.md (42 lines)
- ziglang/zig — https://codeberg.org/ziglang/zig/raw/branch/master/README.md (815 lines; GitHub repo now a Codeberg-move tombstone)
- tinygo-org/tinygo — https://raw.githubusercontent.com/tinygo-org/tinygo/dev/README.md (159 lines)
- oven-sh/bun — https://raw.githubusercontent.com/oven-sh/bun/main/README.md (446 lines)
- denoland/deno — https://raw.githubusercontent.com/denoland/deno/main/README.md (116 lines)
- tokio-rs/tokio — https://raw.githubusercontent.com/tokio-rs/tokio/master/README.md (261 lines)
- tauri-apps/tauri — https://raw.githubusercontent.com/tauri-apps/tauri/dev/README.md (96 lines)
- rust-lang/rust-analyzer — https://raw.githubusercontent.com/rust-lang/rust-analyzer/master/README.md (66 lines)
- bytecodealliance/wasmtime — https://raw.githubusercontent.com/bytecodealliance/wasmtime/main/README.md (184 lines)
- dtolnay/cxx — https://raw.githubusercontent.com/dtolnay/cxx/master/README.md (387 lines)
- ihciah/rust2go — https://raw.githubusercontent.com/ihciah/rust2go/master/README.md (153 lines)
- sharkdp/bat — https://raw.githubusercontent.com/sharkdp/bat/master/README.md (941 lines)
- BurntSushi/ripgrep — https://raw.githubusercontent.com/BurntSushi/ripgrep/master/README.md (541 lines)
- junegunn/fzf — https://raw.githubusercontent.com/junegunn/fzf/master/README.md (1153 lines)

Star counts from the GitHub REST API (`/repos/<owner>/<repo>`), fetched this session;
bat's star count estimated (~51k) after one rate-limited response. Web content was
treated strictly as data.
