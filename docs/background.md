# Background (outline: jose writes the prose)

<!-- TEMPLATE. Replace each "TODO (jose)" with your own text. Keep the facts and sources. -->

## Threaded code, and why this kernel is indirect-threaded

TODO (jose): intro paragraph.

- Term from James R. Bell, 1973: [CACM 16(6)](https://dl.acm.org/doi/10.1145/362248.362270)
- Variants (direct, indirect, subroutine, token): [Ertl, threaded code](https://www.complang.tuwien.ac.at/forth/threaded-code.html); [Rodriguez, Moving Forth part 1](https://www.bradrodriguez.com/papers/moving1.htm)
- Facts from this repo:
  - the kernel is ITC; colon definitions are lists of code-field addresses (`kernel.lisp`);
  - the on-chip compiler only appends cells (`,`); every instruction comes from the host assembler.
- Cost: one extra load per executed word ("double indirection", Rodriguez).
- TODO (jose): your view of subroutine threading on a Cortex-M.

## NEXT on two machines

TODO (jose): paragraph.

- Thumb-2 NEXT, exactly as `kernel.lisp` emits it: `ldr.w r7,[r4],#4` / `ldr.w r0,[r7]` / `bx r0`
- Registers: r4 IP, r5 data-stack pointer, r6 TOS, r7 W, sp return stack
- Z80: 16-bit cells, 64 KiB, 8-bit ALU. The register map is in `z80/NOTES.md`.
- Rodriguez: direct threading shortens a Z80 NEXT from 11 to 7 instructions ([Moving Forth part 1](https://www.bradrodriguez.com/papers/moving1.htm))
- TODO (jose): STM32 vs Z80 comparison table (cell size, address space, integers, floats, emulator).

## SBCL as an assembler breadboard

TODO (jose): paragraph.

- Source: [Khuong, SBCL: the ultimate assembly code breadboard](https://pvk.ca/Blog/2014/03/15/sbcl-the-ultimate-assembly-code-breadboard/): `sb-assem`, `define-vop`, assemble, disassemble and run in one REPL session
- SBCL backends target only real SBCL ports ([`src/compiler/`](https://github.com/sbcl/sbcl/tree/master/src/compiler)). Here, only the `sb-assem` segments and labels are reused; the encoders are plain Lisp functions, tested against GNU as.
- Finding: SBCL 2.6.9 `emit-back-patch` resolved only the first of adjacent references to one label. The assembler keeps its own fixup list, with a regression test.

## Lisp in flight software

TODO (jose): paragraph.

- Galileo magnetometer, 1993: an RCA 1802 with 2 KiB RAM and 2 KiB ROM, and a corrupted byte. A Lisp-built Forth environment and simulator delivered the patch in about 3 months of part-time work ([Lisping at JPL](https://flownet.com/gat/jpl-lisp.html); [gll-mag-patch](https://github.com/rongarret/gll-mag-patch): `compiler-test`, `compile-patch`, `Patches/test results`)
- Deep Space 1 Remote Agent, 1999: a race condition missed on the ground was diagnosed through a REPL on the spacecraft ([Lisping at JPL](https://flownet.com/gat/jpl-lisp.html)). Model checking reproduced it afterwards ([Havelund, NTRS 20000055731](https://ntrs.nasa.gov/api/citations/20000055731/downloads/20000055731.pdf); [NTRS 20210001175](https://ntrs.nasa.gov/citations/20210001175))
- Lessons to state in your words:
  - build the simulator first;
  - prove the toolchain reproduces known bytes;
  - keep a live REPL;
  - expect concurrency bugs to survive testing.

## R7RS-small, and where this Scheme stands

TODO (jose): paragraph.

- [r7rs.org](https://r7rs.org/); [final report](https://small.r7rs.org/attachment/r7rs.pdf), ratified 2013
- Suite: [chibi-scheme tests/r7rs-tests.scm](https://github.com/ashinn/chibi-scheme/blob/master/tests/r7rs-tests.scm), vendored unmodified. The counts are in "Test results by layer"; `skip.scm` names a reason for every skip.
- Known gaps: syntax-rules not hygienic; call/cc escape-only; single floats; no bignums, Unicode or file ports.
