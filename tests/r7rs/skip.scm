; skip.scm -- tests that cannot run yet on the chip Scheme, with the reason.
; Read by host.lisp (suite.lisp). Entries:
;   (section "NAME" "reason")   every test in that test-begin section
;   (head "NAME" "reason")      forms whose head, or a nested test, is NAME
;   (match "TEXT" "reason")     forms whose text contains TEXT
;   (nonlatin1 "" "reason")    forms with a character beyond Latin-1
;   (literal "KIND" "reason")   forms with a number literal of KIND: bignum float ratio complex prefix
; Remove an entry when the feature lands; the skip count must only go down.
(head "import" "no libraries: (import ...) not supported")
(head "test-numeric-syntax" "no string->number / number->string")
(head "test-precision" "no inexact reals")
(head "test-read-error" "no read procedure or ports")
(head "test-write-syntax" "no ports: write to string")
(section "6.12 Environments and evaluation" "no eval / environments")
(section "6.13 Input and output" "no ports beyond the console")
(section "6.14 System interface" "no system interface")
(section "Read syntax" "no read procedure or ports")
(section "Numeric syntax" "no string->number")
(match "string->number" "no string->number")
(match "number->string" "no number->string")
(literal "bignum" "no bignums: fixnums are 31-bit, beyond that is an overflow error")
(literal "complex" "no complex numbers")
(literal "prefix" "no #e #i #x #b #o #d number prefixes")
(nonlatin1 "" "no Unicode: characters and strings are bytes; the serial link is Latin-1")
