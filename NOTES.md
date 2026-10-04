# Assembly -> SBCL breadboard -> Forth -> Lisp on the STM32F446

One emulated STM32F446 (Cortex-M4F, 128 KiB RAM, 512 KiB flash). Every layer is built here,
from Thumb-2 machine code up; no third-party Forth (Mecrisp-Stellaris, used before
2026-10-04, is gone, and with it the GPLv3 question). All published numbers are measured
on this stack: `asm-tests.txt`, `kernel-tests.txt`, `conformance.txt`.

```
 4  LISP     R7RS-small subset Scheme, written in Forth words (lisp.fs), loaded through
             the Forth console; prims.lisp + prelude.scm on top.         tests: r7rs-tests.scm
             ------------------------------------------------------------------------
 3  FORTH    our own indirect-threaded Forth kernel on the chip: primitives in Thumb-2,
             outer interpreter in Forth (kernel.fs), dictionary, serial console.
                                                                         tests: forth-tests.txt
             ------------------------------------------------------------------------
 2  SBCL     breadboard on the host: a Thumb-2 assembler on SBCL's sb-assem segments,
             VOP-style primitive templates, a metacompiler for kernel.fs, image writer.
                                                                         tests: asm-tests (vs GNU as)
             ------------------------------------------------------------------------
 1  ASM      Thumb-2 / ARMv7-M instructions (and FPv4-SP for floats)     tests: byte-exact encodings
```

Each layer has its own tests, run in this order: assembler encodings (byte-identical to
`arm-none-eabi-as`), kernel words over the serial console, then the Scheme conformance suite.

## Plan

### Layer 2: the SBCL breadboard

Paul Khuong, "SBCL: the ultimate assembly code breadboard"
(https://pvk.ca/Blog/2014/03/15/sbcl-the-ultimate-assembly-code-breadboard/), writes machine
code from the SBCL REPL with SBCL's own assembler (`sb-assem` segments, `inst`, `define-vop`)
and inspects it with `sb-disassem`. SBCL's backend targets the host (x86-64), so
its instruction definitions and `define-vop` cannot emit Thumb-2, and a VOP cannot run on the
host. The decision:

- **Reuse `sb-assem` for what is ISA-neutral**: segments (`make-segment`, `emit-byte`),
  labels (`gen-label`, `emit-label`, `label-position`), and back-patches (`emit-back-patch`)
  for forward references, branch offsets and absolute cells. Checked on SBCL 2.6.9.
- **Write the Thumb-2 encoders as plain Lisp functions** over those segments, one per
  instruction form, and test each form against `arm-none-eabi-as` byte for byte.
- **VOP-style templates for primitives**: `defcode` takes a Forth name and a body of
  instructions, lays down the dictionary header, and appends `NEXT`, the way a VOP pairs
  a name with a code template.
- The host also metacompiles the high-level kernel (`kernel.fs`) into threaded code, links
  every reference with labels, and writes the flash image.

### Layer 3: the kernel

- **Threading: indirect-threaded code (ITC).** A colon definition is a list of execution
  tokens (cell addresses), so the on-chip compiler only appends cells and never encodes
  instructions. The cost is one extra load per word, which is acceptable for an interpreter host.
- **Registers:** r4 = IP, r5 = data stack pointer (full descending; holds the second item),
  r6 = TOS, r7 = W (current xt), sp = return stack, r0-r3 and r12 scratch.
- **NEXT:** `ldr r7,[r4],#4 ; ldr r0,[r7] ; bx r0`.
- **Header:** link (4 bytes), flags (bit 7 immediate, bit 6 hidden), name length, name,
  pad to 4, then the code field (CFA), then the body. An xt is a CFA address.
- **Memory map:**
  - Flash `0x08000000`: vector table, primitives, kernel headers and threads (read-only).
  - RAM `0x20000000`: system variables and the 512-byte input buffer, then the user dictionary.
  - Data stack: 4 KiB below `0x2001EFE0`.
  - Return stack: 4 KiB below `0x2001FFE0`. QEMU's netduinoplus2 breaks on writes to the last
    32 bytes of RAM, so the stacks stop short of them.
- **Console:** USART2, polled, 115200 baud from the 16 MHz HSI. It is QEMU's second
  `-serial`. `accept` treats Backspace and Delete alike.
- **Compatibility:** the console protocol (` ok.`, `not found.`) and the word set that
  `lisp.fs` uses (`variable` with an initial value, `buffer:`, `token`, `h@`, `cbis!`, ...)
  follow Mecrisp, so layer 4 loads unchanged.
- **Flash writing:** the image is written by the host. A runtime `flash!` follows RM0390
  (unlock keys, PG, PSIZE). QEMU does not model the F4 flash controller, so `flash!` is
  untested in emulation.

## Influences: remote patching of running systems

- **gll-mag-patch** (Ron Garret, JPL 1993; https://github.com/rongarret/gll-mag-patch).
  Galileo's magnetometer ran Forth on an RCA 1802. A RAM byte had failed, and the original
  development system no longer worked (README). Garret rebuilt the toolchain in Macintosh
  Common Lisp:
  - `forthcomp.lisp` rebuilds the flight dictionary from the ROM and RAM images and their
    word index (`build-gll-dictionary`).
  - `compiler-test` recompiles every recovered RAM word from `ram source.lisp` and diffs it
    byte for byte against the flight RAM image. This proves the new compiler reproduces the
    old one.
  - `compile-patch` compiles a replacement word at the **old word's address**. It warns when
    the patch overflows the old slot and prints only the bytes that differ. `Patches/delivered`
    holds those address-plus-hex deltas, which are what was uplinked.
  - `Patches/development` frees space by merging the slots of retired words (DSP12 and DSP3)
    into one larger slot for the new word.
  - `sim1802` simulates the 1802; `asm1802` is its assembler; `lisp->forth` and macros such
    as `main-event-loop` generate Forth from Lisp.
  - `Patches/test results` records the instrument team's independent review. They confirmed
    the compiled bytes matched the source, then ran the logic on their own test setup and
    found it still wrong (extra vectors at rim 0 and 90). Review caught the bug before uplink.
  - The flight `MAIN` computes ROM and RAM checksums (`ram source.lisp`).
- **"Lisping at JPL"** (Ron Garret; https://flownet.com/gat/jpl-lisp.html).
  - The magnetometer team had judged the patch too costly to attempt. A Lisp-built Forth
    environment with a hardware simulator delivered it in under three months of part-time work.
  - On Deep Space 1, a Lisp REPL running on the spacecraft let the team find and fix a race
    condition that ground testing had missed, about 100 million miles away.
  - Earlier robots used Lisp-hosted compilers for small targets, for example a 68HC11
    with 256 bytes of RAM.

What this design takes from them:
- The host holds the full development system: assembler, metacompiler, simulator-like tests.
- The target keeps a live interpreter, so code can be redefined over the serial link.
- The compiler is proven by reproducing known-good bytes, as `compiler-test` did.
- Patches are small, addressed, size-checked deltas. Each one is reviewed and tested off the
  target before it is sent.

## Status

| Layer | Test | Result |
|---|---|---|
| 1-2 assembler | `asm-test.lisp`: every encoder form vs `arm-none-eabi-as` (incl. FPv4-SP), plus repeated label references | 105/105 |
| 3 kernel | `forth-tests.txt` via `host.lisp ktest`, fresh boot | 71/71 |
| 4 Scheme | chibi-scheme's R7RS suite, `tests/r7rs/`, via `host.lisp suite` | see `tests/r7rs/results.txt` |
| 4 Scheme | our own regression suite `r7rs-tests.scm` via `host.lisp test` | 390/390 |

- Kernel image: about 10.4 KiB of flash, 197 words (FPU words `f+ f- f* f/ s>f f>s fsqrt f< f=`).
- RAM after `lisp.fs`, `prims.lisp` and `prelude.scm` load:
  - cons heap 60 KiB (7679 cells);
  - blob heap 12 KiB;
  - symbol names 10 KiB;
  - 5.9 KiB of dictionary free (`unused` = 5928).
  The prelude grew with item 4. At 48 KiB of heap, the 20000-iteration tail-call test spent
  most of its time in GC.
- The kernel prints `Redefine NAME.` when a definition shadows an existing word, and `host.lisp`
  stops the load on it. A list-length word named `llen` once silently captured the reader's
  `llen` variable in every later word.
- `lisp.fs` loaded unchanged: the kernel follows Mecrisp's console protocol and word set.
- Gotcha: sb-assem's `emit-back-patch` (SBCL 2.6.9) resolved only the first of several adjacent
  references to one label, which left zero cells in the vector table and `li` loads.
  `asm.lisp` now keeps its own fixup list; `asm-test.lisp` has a regression case for it.
- A Z80 machine built the same way (own Z80 kernel, SBCL Z80 assembler, z80pack cpmsim)
  lives in `z80/`; see `z80/NOTES.md`.
## Conformance

**Target: the full R7RS-small suite of chibi-scheme** (Alex Shinn; `tests/r7rs-tests.scm`,
1132 test calls; BSD licence, kept in `tests/r7rs/LICENSE`), vendored unmodified in `tests/r7rs/`.
- `host.lisp suite` splits the file into top-level forms and sends each one to the chip as one
  line (the longest is 454 bytes; the line buffer is 512).
- `shim.scm` defines `test`, `test-assert`, `test-begin` and `test-end` as chip procedures that
  print a pass or fail marker.
- `skip.scm` lists what cannot run yet, by section, test head, text or number-literal kind,
  each with a reason. A test that uses a name whose definition was skipped is skipped with
  that reason too. `results.txt` counts the skips per reason; no test is deleted.
- A form that errors counts all of its unreported tests as failed. If the chip stops
  answering, every later test counts as failed.
- First run on the own stack: 244 passed, 78 failed, 810 skipped, 1132 total. After item 1 (numbers): 302 passed, 119 failed, 711 skipped. After item 2 (characters,
  strings, vectors, bytevectors): 486 passed, 123 failed, 523 skipped. After item 3 (sqrt,
  rounding): 500 passed, 109 failed, 523 skipped. After items 4 and 5 (macros, call/cc,
  dynamic-wind, exceptions, raisable primitive errors, values, promises, parameters, records):
  603 passed, 140 failed, 389 skipped. It found two
  bugs, now fixed and covered by local regression tests: `list?` looped on a circular list,
  and `case` lacked `=>`.

Our own suite below stays local: a reported sieve program, string cases and those regressions.

`r7rs-tests.scm` holds 205 cases, most of them the examples of R7RS-small sections 4.1, 4.2, 5.3, 6.1-6.5, 6.7, 6.8 and 6.10, a 20000-iteration tail-call loop, and a regression case: a multi-line Sieve of Eratosthenes with a docstring, vectors, `do`, `when` and named let. `host.lisp test` sends each to the emulated chip and compares the printed result. Last run: see `conformance.txt` (205 passed, 0 failed).

### Supported

- Special forms: `quote` `'x` `if` `define` (variables, procedures, internal defines) `set!` `lambda` (fixed, dotted and rest parameters) `begin` `let` (and named let) `let*` `letrec` `letrec*` `cond` (with `else` and `=>`) `case` `and` `or` `when` `unless` `do`.
- Data: exact integers, strings (escapes `\"` `\\` `\n` `\t`; may span lines), vectors (`#(...)`), symbols, pairs and lists, `#t` `#f` (also `#true` `#false`), `'()` distinct from `#f`, procedures.
- Procedures: `+ - * quotient remainder modulo = < > <= >= eq? eqv? equal? car cdr cons set-car! set-cdr! null? pair? list? symbol? number? integer? exact? exact-integer? inexact? boolean? procedure? apply display write newline string? vector? list->string list->vector make-vector vector-ref vector-set!` and, from `prelude.scm`, `not caar cadr cdar cddr caddr list length reverse append list-tail list-ref list-copy make-list map for-each memq memv member assq assv assoc zero? positive? negative? odd? even? abs max min gcd lcm square boolean=? symbol=? string->list string-length string=? string-append vector vector->list vector-length floor ceiling round truncate exact inexact sqrt exact-integer-sqrt`.
- Proper tail calls in `if`, `cond`, `case`, `and`, `or`, `when`, `unless`, `let` forms, `begin`, `do` and procedure bodies.

### Deviations from R7RS-small

- Numbers: exact integers are 31-bit fixnums; a result outside -2^30..2^30-1 raises `overflow`
  (no bignums; 64-bit products are checked with `m*`). Exact rationals are normalized fixnum
  pairs. Inexact reals are IEEE **single** precision on the M4F FPU (R7RS expects double):
  about 7 significant digits. Printing uses 7 digits and the last one can be off by one, so
  output need not read back to the same float. No complex numbers, no `exp`/`log`/trig yet.
- Characters are bytes (Latin-1): no Unicode, since the serial console and the string storage
  are 8-bit. Strings, vectors and bytevectors live in a 16 KiB blob heap, with O(1) access.
  The GC compacts live blobs. Missing from the string library: `string-fill!`, `string-copy!`,
  case conversion of whole strings, and `-ci` string comparisons.
- `sqrt` is exact for exact squares (`(sqrt 1/4)` is `1/2`) and inexact otherwise. A negative argument gives `+nan.0`, because there are no complex numbers. `exact-integer-sqrt` returns a list `(s r)` until multiple values exist. `floor`, `ceiling`, `truncate` and `round` (half to even) handle rationals and floats. No `exp`, `log` or trigonometry yet.
- Macros: `define-syntax`, `let-syntax`, `letrec-syntax` and `syntax-rules` (with literals, `_`,
  nested ellipses, custom ellipsis, `(... ...)`) are **not hygienic**. A template symbol means
  whatever it means where the expansion lands. `quasiquote`, `delay`, `delay-force`, `guard`,
  `parameterize`, `define-record-type`, `case-lambda`, `let-values` and `define-values` are
  procedural macros in `prelude.scm`. `let-values` binds left to right, like `let*-values`.
- `call/cc` is **escape-only**. A continuation works while its `call/cc` is still active.
  Calling it later is an error. There is no re-entry and no generators. `dynamic-wind` runs the
  *after* thunks when an escape leaves its extent.
- Exceptions: `raise`, `raise-continuable`, `with-exception-handler`, `guard`, `error` and
  error objects. Errors from primitives (`car` of a non-pair, a vector index out of range, an
  unbound variable, ...) raise error objects when a handler is installed. Uncaught errors print
  their message and irritants and return to the prompt. A `guard` with no matching clause
  re-raises in the dynamic environment of the `guard`, not of the original `raise`. `too deep`
  and `out of memory` are never raisable, because recovering needs the stack or heap they
  report as exhausted.
- Symbols are never garbage collected. Their names share a 10 KiB buffer.
- No libraries (`import`) and no ports beyond the console yet.
- Primitives check their argument count (a table in `prelude.scm`); a wrong count raises
  `wrong number of arguments`. Closures check theirs (`too few arguments`, `too many arguments`).
- Recursion depth is bounded by the 4 KiB stacks: non-tail recursion raises `too deep` between 150 and 200 levels (measured with `(d 150)` and `(d 200)`).
- `define` returns an unspecified value. The REPL echoes the name of a top-level `define` or
  `define-syntax` as a convenience; the name is not the value.

## Implementation

- Values are 32-bit. Low bits: `xx1` fixnum, `000` pair (0 is `'()`), `010` symbol, `100` immediate (`#f` `#t`, unspecified, unbound, special-form markers), `110` procedure. Cells are 8 bytes (car, cdr) in a 64 KiB heap (8191 cells).
- A symbol's cdr is its global value. A special form name is bound to a marker value, so a local variable of the same name shadows it.
- An environment is an alist in front of the globals. Each procedure call and `let` adds a dummy binding first, so an internal `define` can splice its binding in after the head without touching the enclosing scope.
- `eval` is a loop: special-form handlers return either a value or a new (expression, environment) pair, which is how tail calls run in constant stack.
- GC: mark-sweep, run when `cons` finds the free list empty. Roots are the symbol list and every word on the data and return stacks that looks like a heap reference (conservative scan), so a GC inside a running expression is safe.
- Reader: lines come from Mecrisp's `accept`, which handles Backspace (0x08) and Delete (0x7f) and echoes the erase; the reader then parses from that line buffer (512 bytes). An expression may span lines.

## Serial driving

The host sends one character at a time and waits for the echo, then waits for ` ok.` (Forth) or `> ` (Scheme). The emulated USART has a one-byte receive register.

## Files

- `host.lisp` -- compiler and serial driver: `compile FILE | load | demo | test [FILE] | eval EXPR... | forth LINE...`.
- `lisp.fs` -- the chip Scheme: values, GC, symbols, reader, printer, eval, special forms, Forth-side primitives, REPL.
- `prims.lisp` -- arithmetic, comparison and type primitives in the host dialect.
- `prelude.scm` -- library procedures in Scheme, one form per line.
- `r7rs-tests.scm`, `conformance.txt` -- the conformance subset and its last result.
- `demo.lisp`, `demo.sh`, `transcript.txt` -- scripted proof of all three layers.
- `build-firmware.sh` -- the F446 Mecrisp build. The image is not committed; the launchers build it when missing.
- `stm32-lisp`, `stm32-forth` -- launchers (QEMU netduinoplus2).

## Sources used

- Ron Garret, gll-mag-patch (`forthcomp.lisp`, README) and "Lisp at JPL" (flownet.com/gat/jpl-lisp.html).
- R7RS-small report (r7rs.org) for the forms, procedures and test examples.
- Mecrisp-Stellaris 2.6.5 source (`common/forth-core.s` stack sizes, `common/query.s` accept, `stm32f407/` port).
