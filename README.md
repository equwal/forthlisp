# forthlisp

A Scheme that runs on a small chip, on top of a Forth kernel built for that chip, on top of
machine code assembled by Lisp on the host. Every layer is built from scratch. This repo
holds the parts that both targets share: the host-side Lisp, the Scheme (written in Forth
words), the R7RS test harness and the reference-page generator.

```
 4  LISP     R7RS-small subset Scheme, written in Forth words (lisp.fs), loaded through
             the chip's Forth console; prims.lisp + prelude.scm on top
 3  FORTH    the target's own Forth kernel (in the target repo)
 2  SBCL     breadboard on the host: assembler, primitive templates, metacompiler,
             serial driver, test harness (host.lisp, suite.lisp here; assemblers in the targets)
 1  ASM      the target's instructions: Thumb-2 (STM32F446) or Z80
```

Targets:

- [forthlisp-stm32](https://github.com/equwal/forthlisp-stm32): STM32F446 (Cortex-M4F) in QEMU `netduinoplus2`
- [forthlisp-z80](https://github.com/equwal/forthlisp-z80): Z80 in z80pack `cpmsim`

Reference page with cheat sheets and the full spec: https://dickt.store/forthlisp/

## Quickstart

Check out this repo next to a target repo; the targets find it at `../forthlisp` (or set
`FORTHLISP_CORE`):

```sh
git clone https://github.com/equwal/forthlisp
git clone https://github.com/equwal/forthlisp-stm32
cd forthlisp-stm32 && ./build-firmware.sh && ./stm32-lisp
```

Needs SBCL, `qemu-system-arm`, `arm-none-eabi-as`/`objcopy` (for the assembler tests), and
`nc`. At the `>` prompt, type Scheme. `(forth)` returns to the Forth prompt.

## Files

- `host.lisp`: host compiler for a small Lisp dialect into Forth words, the serial
  driver, and the commands `load`, `demo`, `ktest`, `test`, `suite`, `eval`, `forth`
- `lisp.fs`: the Scheme in Forth: tagged values, mark-sweep GC with a conservative stack
  scan, a compacting blob heap for strings, vectors and bytevectors, a tail-calling eval,
  the reader and the printer
- `prims.lisp`: arithmetic and type primitives, written in the host dialect
- `prelude.scm`: library procedures written in the chip Scheme
- `r7rs-tests.scm`: our own regression suite (`EXPR ==> printed result`)
- `tests/r7rs/`: chibi-scheme's R7RS-small suite, vendored unmodified (BSD, see its
  `LICENSE`), with `shim.scm`, the machine-readable `skip.scm` and `results.txt`
- `suite.lisp`: runs that suite over the serial link
- `docs/build-docs.py`: generates the reference page from the sources

## Test counts (STM32F446 target, QEMU)

- Our regression suite: see `conformance.txt` (317/317 at publication)
- chibi-scheme R7RS suite: see `tests/r7rs/results.txt` (500 passed, 109 failed, 523 skipped
  of 1132 at publication; every skip names its reason)

## Limits

- Fixnums are 31-bit; overflow is an error, and there are no bignums.
- Inexact reals are IEEE single precision (the M4F FPU); R7RS expects double.
- Characters are bytes; there is no Unicode.
- No `define-syntax`, `call/cc`, `dynamic-wind`, exceptions, parameters, records,
  libraries or ports yet. `NOTES.md` lists every deviation.

## Influences

- Paul Khuong, "SBCL: the ultimate assembly code breadboard"
  (https://pvk.ca/Blog/2014/03/15/sbcl-the-ultimate-assembly-code-breadboard/): machine code
  written and tested from the SBCL REPL. The assemblers here reuse SBCL's `sb-assem` segments
  and labels.
- Ron Garret, gll-mag-patch (https://github.com/rongarret/gll-mag-patch): a Lisp-hosted Forth
  toolchain that rebuilt and patched the Galileo magnetometer's flight code.
- Ron Garret, "Lisping at JPL" (https://flownet.com/gat/jpl-lisp.html): the live REPL on
  Deep Space 1, and why a patchable live image matters.

## Licence

MIT (see `LICENSE`). `tests/r7rs/r7rs-tests.scm` is chibi-scheme's, under its BSD licence
(`tests/r7rs/LICENSE`).
