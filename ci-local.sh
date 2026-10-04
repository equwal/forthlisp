#!/bin/sh
# ci-local.sh -- CI for the three public repos without a hosted CI service. It replays the
# jobs in a clean ubuntu:24.04 container: clone equwal/forthlisp, -stm32 and -z80 over https,
# install the toolchain from Ubuntu, run every test layer. Needs docker.
# Prints one summary line per job, then "CI: PASS" or "CI: FAIL".
docker run --rm ubuntu:24.04 sh -c '
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq sbcl qemu-system-arm binutils-arm-none-eabi build-essential git ca-certificates >/dev/null || exit 1
cd "$HOME" && for r in forthlisp forthlisp-stm32 forthlisp-z80; do git clone -q https://github.com/equwal/$r || exit 1; done
rc=0
echo "repos: $(for r in forthlisp forthlisp-stm32 forthlisp-z80; do printf "%s@%s " $r $(git -C $r rev-parse --short HEAD); done)"
cd "$HOME/forthlisp" && { sbcl --script host.lisp compile prims.lisp >/dev/null && sbcl --script host.lisp compile demo.lisp >/dev/null && echo "core host: compile ok"; } || { echo "core host: FAIL"; rc=1; }
cd "$HOME/forthlisp-stm32" && { sh test.sh || rc=1; }
cd "$HOME/forthlisp-z80" && { sh build-emu.sh >/dev/null && sh test.sh || rc=1; }
[ $rc = 0 ] && echo "CI: PASS" || echo "CI: FAIL"
exit $rc
'