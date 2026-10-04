; r7rs-tests.scm -- conformance subset, run on the emulated chip by: host.lisp test
; Each line: EXPR ==> printed result. Most cases are the examples of R7RS-small
; (sections 4.1, 4.2, 5.3, 6.1, 6.2, 6.3, 6.4, 6.10); a line without ==> only has to evaluate.
; 4.1.1 variables, 4.1.2 literals
(define x 28) ==> x
x ==> 28
(quote a) ==> a
'a ==> a
'(+ 1 2) ==> (+ 1 2)
'() ==> ()
'#t ==> #t
145932 ==> 145932
#t ==> #t
#false ==> #f
; 4.1.3 procedure calls
(+ 3 4) ==> 7
((if #f + *) 3 4) ==> 12
; 4.1.4 lambda
((lambda (x) (+ x x)) 4) ==> 8
(define reverse-subtract (lambda (x y) (- y x))) ==> reverse-subtract
(reverse-subtract 7 10) ==> 3
(define add4 (let ((x 4)) (lambda (y) (+ x y)))) ==> add4
(add4 6) ==> 10
((lambda x x) 3 4 5 6) ==> (3 4 5 6)
((lambda (x y . z) z) 3 4 5 6) ==> (5 6)
; 4.1.5 if
(if (> 3 2) 'yes 'no) ==> yes
(if (> 2 3) 'yes 'no) ==> no
(if (> 3 2) (- 3 2) (+ 3 2)) ==> 1
; 4.1.6 set!
(define y 2) ==> y
(+ y 1) ==> 3
(set! y 4)
(+ y 1) ==> 5
; 4.2.1 cond, case, and, or, when, unless
(cond ((> 3 2) 'greater) ((< 3 2) 'less)) ==> greater
(cond ((> 3 3) 'greater) ((< 3 3) 'less) (else 'equal)) ==> equal
(cond ((assv 'b '((a 1) (b 2))) => cadr) (else #f)) ==> 2
(case (* 2 3) ((2 3 5 7) 'prime) ((1 4 6 8 9) 'composite)) ==> composite
(case (car '(c d)) ((a e i o u) 'vowel) ((w y) 'semivowel) (else 'consonant)) ==> consonant
(and (= 2 2) (> 2 1)) ==> #t
(and (= 2 2) (< 2 1)) ==> #f
(and 1 2 'c '(f g)) ==> (f g)
(and) ==> #t
(or (= 2 2) (> 2 1)) ==> #t
(or (= 2 2) (< 2 1)) ==> #t
(or #f #f #f) ==> #f
(or (memq 'b '(a b c)) (/ 3 0)) ==> (b c)
(when (= 1 1) 'a 'b) ==> b
(unless (= 1 1) 'a 'b) ==>
; 4.2.2 binding constructs
(let ((x 2) (y 3)) (* x y)) ==> 6
(let ((x 2) (y 3)) (let ((x 7) (z (+ x y))) (* z x))) ==> 35
(let ((x 2) (y 3)) (let* ((x 7) (z (+ x y))) (* z x))) ==> 70
(letrec ((even? (lambda (n) (if (zero? n) #t (odd? (- n 1))))) (odd? (lambda (n) (if (zero? n) #f (even? (- n 1)))))) (even? 88)) ==> #t
(letrec* ((p (lambda (x) (+ 1 (q (- x 1))))) (q (lambda (y) (if (zero? y) 0 (+ 1 (p (- y 1)))))) (x (p 5)) (y x)) y) ==> 5
; 4.2.3 sequencing
(define x 0) ==> x
(begin (set! x 5) (+ x 1)) ==> 6
; 4.2.4 iteration
(let loop ((numbers '(3 -2 1 6 -5)) (nonneg '()) (neg '())) (cond ((null? numbers) (list nonneg neg)) ((>= (car numbers) 0) (loop (cdr numbers) (cons (car numbers) nonneg) neg)) ((< (car numbers) 0) (loop (cdr numbers) nonneg (cons (car numbers) neg))))) ==> ((6 1 3) (-5 -2))
(let ((x '(1 3 5 7 9))) (do ((x x (cdr x)) (sum 0 (+ sum (car x)))) ((null? x) sum))) ==> 25
; 5.3 definitions, internal definitions
(define add3 (lambda (x) (+ x 3))) ==> add3
(add3 3) ==> 6
(define first car) ==> first
(first '(1 2)) ==> 1
(let ((x 5)) (define foo (lambda (y) (bar x y))) (define bar (lambda (a b) (+ (* a b) a))) (foo (+ x 3))) ==> 45
; 6.1 equivalence
(eqv? 'a 'a) ==> #t
(eqv? 'a 'b) ==> #f
(eqv? 2 2) ==> #t
(eqv? '() '()) ==> #t
(eqv? 100000000 100000000) ==> #t
(eqv? (cons 1 2) (cons 1 2)) ==> #f
(eqv? (lambda () 1) (lambda () 2)) ==> #f
(eqv? #f 'nil) ==> #f
(let ((p (lambda (x) x))) (eqv? p p)) ==> #t
(eq? 'a 'a) ==> #t
(eq? (list 'a) (list 'a)) ==> #f
(eq? '() '()) ==> #t
(eq? car car) ==> #t
(let ((x '(a))) (eq? x x)) ==> #t
(equal? 'a 'a) ==> #t
(equal? '(a) '(a)) ==> #t
(equal? '(a (b) c) '(a (b) c)) ==> #t
(equal? 2 2) ==> #t
; 6.2 numbers (exact integers only)
(integer? 3) ==> #t
(number? 'a) ==> #f
(= 1 1 1) ==> #t
(< 1 2 3) ==> #t
(< 1 3 2) ==> #f
(>= 3 3 1) ==> #t
(zero? 0) ==> #t
(positive? -5) ==> #f
(odd? 7) ==> #t
(even? 0) ==> #t
(max 3 4) ==> 4
(min 3 4 -1) ==> -1
(+ 3 4) ==> 7
(+ 3) ==> 3
(+) ==> 0
(* 4) ==> 4
(*) ==> 1
(- 3 4) ==> -1
(- 3 4 5) ==> -6
(- 3) ==> -3
(abs -7) ==> 7
(quotient 17 5) ==> 3
(remainder 17 5) ==> 2
(modulo 17 5) ==> 2
(modulo 17 -5) ==> -3
(remainder 17 -5) ==> 2
(modulo -17 5) ==> 3
(remainder -17 5) ==> -2
(gcd 32 -36) ==> 4
(gcd) ==> 0
(lcm 32 -36) ==> 288
(lcm) ==> 1
(square 42) ==> 1764
; 6.3 booleans
#t ==> #t
'#f ==> #f
(not #t) ==> #f
(not 3) ==> #f
(not (list 3)) ==> #f
(not #f) ==> #t
(not '()) ==> #f
(not (list)) ==> #f
(not 'nil) ==> #f
(boolean? #f) ==> #t
(boolean? 0) ==> #f
(boolean? '()) ==> #f
; 6.4 pairs and lists
(define x (list 'a 'b 'c)) ==> x
(define y x) ==> y
(list? y) ==> #t
(set-cdr! x 4)
x ==> (a . 4)
(eqv? x y) ==> #t
y ==> (a . 4)
(list? y) ==> #f
(pair? '(a . b)) ==> #t
(pair? '(a b c)) ==> #t
(pair? '()) ==> #f
(cons 'a '()) ==> (a)
(cons '(a) '(b c d)) ==> ((a) b c d)
(cons 'a 3) ==> (a . 3)
(cons '(a b) 'c) ==> ((a b) . c)
(car '(a b c)) ==> a
(car '((a) b c d)) ==> (a)
(car '(1 . 2)) ==> 1
(cdr '((a) b c d)) ==> (b c d)
(cdr '(1 . 2)) ==> 2
(list? '(a b c)) ==> #t
(list? '()) ==> #t
(list? '(a . b)) ==> #f
(make-list 2 3) ==> (3 3)
(list 'a (+ 3 4) 'c) ==> (a 7 c)
(list) ==> ()
(length '(a b c)) ==> 3
(length '(a (b) (c d e))) ==> 3
(length '()) ==> 0
(append '(x) '(y)) ==> (x y)
(append '(a) '(b c d)) ==> (a b c d)
(append '(a (b)) '((c))) ==> (a (b) (c))
(append '(a b) '(c . d)) ==> (a b c . d)
(append '() 'a) ==> a
(reverse '(a b c)) ==> (c b a)
(reverse '(a (b c) d (e (f)))) ==> ((e (f)) d (b c) a)
(list-tail '(a b c d) 2) ==> (c d)
(list-ref '(a b c d) 2) ==> c
(memq 'a '(a b c)) ==> (a b c)
(memq 'b '(a b c)) ==> (b c)
(memq 'a '(b c d)) ==> #f
(memq (list 'a) '(b (a) c)) ==> #f
(member (list 'a) '(b (a) c)) ==> ((a) c)
(memv 101 '(100 101 102)) ==> (101 102)
(define e '((a 1) (b 2) (c 3))) ==> e
(assq 'a e) ==> (a 1)
(assq 'b e) ==> (b 2)
(assq 'd e) ==> #f
(assq (list 'a) '(((a)) ((b)) ((c)))) ==> #f
(assoc (list 'a) '(((a)) ((b)) ((c)))) ==> ((a))
(assv 5 '((2 3) (5 7) (11 13))) ==> (5 7)
(list-copy '(1 2 3)) ==> (1 2 3)
; 6.5 symbols
(symbol? 'foo) ==> #t
(symbol? (car '(a b))) ==> #t
(symbol? 'nil) ==> #t
(symbol? '()) ==> #f
(symbol=? 'a 'a) ==> #t
; 6.10 control features
(procedure? car) ==> #t
(procedure? 'car) ==> #f
(procedure? (lambda (x) (* x x))) ==> #t
(procedure? '(lambda (x) (* x x))) ==> #f
(apply + (list 3 4)) ==> 7
(apply + 1 2 '(3 4)) ==> 10
(map cadr '((a b) (d e) (g h))) ==> (b e h)
(map + '(1 2 3) '(10 20 30)) ==> (11 22 33)
(map (lambda (n) (* n n)) '(1 2 3 4 5)) ==> (1 4 9 16 25)
(let ((v '())) (for-each (lambda (x) (set! v (cons x v))) '(1 2 3)) v) ==> (3 2 1)
; proper tail calls (3.5): a loop of 20000 iterations runs in constant stack
(define (count n) (if (= n 0) 'done (count (- n 1)))) ==> count
(count 20000) ==> done
; 6.7 strings (regression: a string literal with spaces must read as one string)
"hello world" ==> "hello world"
(string? "a b") ==> #t
(string-length "a b c") ==> 5
(string->list "ab") ==> (#\a #\b)
"say \"hi\" \\ ok" ==> "say \"hi\" \\ ok"
(equal? "a b" "a b") ==> #t
(begin (display "a b") 'x) ==> a bx
; 6.8 vectors
(make-vector 3 0) ==> #(0 0 0)
(let ((v (make-vector 3 #t))) (vector-set! v 1 #f) v) ==> #(#t #f #t)
(vector-ref '#(1 2 3) 2) ==> 3
(vector-length (make-vector 7 1)) ==> 7
(vector->list (vector 1 2 3)) ==> (1 2 3)
; sqrt/floor on exact integers
(sqrt 16) ==> 4
(floor (sqrt 500)) ==> 22.0
(floor 7) ==> 7
; regression: a reported sieve program, a docstring body, vectors, do, when, named let
(define (sieve-of-eratosthenes n) "Return list of primes up to n." (if (< n 2) '() (let ((marked (make-vector (+ n 1) #t))) (vector-set! marked 0 #f) (vector-set! marked 1 #f) (do ((i 2 (+ i 1))) ((> i (floor (sqrt n)))) (when (vector-ref marked i) (do ((j (* i i) (+ j i))) ((> j n)) (vector-set! marked j #f)))) (let loop ((i 2) (primes '())) (if (> i n) (reverse primes) (loop (+ i 1) (if (vector-ref marked i) (cons i primes) primes))))))) ==> sieve-of-eratosthenes
(sieve-of-eratosthenes 500) ==> (2 3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71 73 79 83 89 97 101 103 107 109 113 127 131 137 139 149 151 157 163 167 173 179 181 191 193 197 199 211 223 227 229 233 239 241 251 257 263 269 271 277 281 283 293 307 311 313 317 331 337 347 349 353 359 367 373 379 383 389 397 401 409 419 421 431 433 439 443 449 457 461 463 467 479 487 491 499)
(length (sieve-of-eratosthenes 500)) ==> 95
; regressions found by the chibi suite: list? must stop on a circular list; case accepts =>
(let ((x (list 'a))) (set-cdr! x x) (list? x)) ==> #f
(case 5 ((2 3 5 7) => (lambda (p) (* p 10))) (else 'no)) ==> 50
(case 'z ((a) 1) (else => (lambda (x) x))) ==> z
; 6.2 numbers: overflow is an error, not a silent wrap (regression)
(+ 1073741823 1) ==> overflow
(* 100000 100000) ==> overflow
(- -1073741824 1) ==> overflow
(* 32768 32768) ==> overflow
(+ 1073741822 1) ==> 1073741823
; 6.2.6 exact rationals and /
(/ 6 4) ==> 3/2
(/ 6 3) ==> 2
(/ 3) ==> 1/3
(/ 3 4 5) ==> 3/20
(+ 1/2 1/3) ==> 5/6
(* 2/3 3/2) ==> 1
(- 1/2) ==> -1/2
(- 1/2 1/3) ==> 1/6
(= 1/2 2/4) ==> #t
(< 1/3 1/2) ==> #t
(exact? 1/2) ==> #t
(rational? 1/2) ==> #t
(integer? 1/2) ==> #f
(numerator (/ 6 4)) ==> 3
(denominator (/ 6 4)) ==> 2
(denominator 5) ==> 1
(/ 1 0) ==> division by zero
; 6.2.6 inexact reals (single precision on the M4F FPU)
(+ 1.5 2.25) ==> 3.75
(* 1.5 2) ==> 3.0
-2.5 ==> -2.5
1e3 ==> 1000.0
(/ 1.0 4) ==> 0.25
(< 0.3333 (/ 1 3.0) 0.3334) ==> #t
(+ 0.1 0.2) ==> 0.3
(- 0.5) ==> -0.5
(inexact 1/4) ==> 0.25
(exact->inexact 1/2) ==> 0.5
(exact 0.5) ==> 1/2
(exact 3.0) ==> 3
(inexact->exact 0.25) ==> 1/4
(inexact? 1.0) ==> #t
(exact? 1.0) ==> #f
(integer? 3.0) ==> #t
(integer? 3.5) ==> #f
(exact-integer? 5) ==> #t
(exact-integer? 5.0) ==> #f
(= 1 1.0) ==> #t
(eqv? 1 1.0) ==> #f
(eqv? 1.5 1.5) ==> #t
(eqv? 1/2 (/ 2 4)) ==> #t
(< 1 1.5 2) ==> #t
(max 3 2.0) ==> 3.0
(min 1 2.0) ==> 1.0
(abs -2.5) ==> 2.5
(/ 1.0 0) ==> +inf.0
(- (/ 1.0 0)) ==> -inf.0
(number? 1.5) ==> #t
(real? 1/2) ==> #t
; item 2: characters, strings with O(1) access, contiguous vectors, bytevectors
#\a ==> #\a
#\space ==> #\space
(char->integer #\A) ==> 65
(integer->char 97) ==> #\a
(char? #\a) ==> #t
(char? "a") ==> #f
(char<? #\a #\b #\c) ==> #t
(char-upcase #\a) ==> #\A
(char-alphabetic? #\z) ==> #t
(char-numeric? #\5) ==> #t
(string->list "ab") ==> (#\a #\b)
(list->string (list #\h #\i)) ==> "hi"
(string-ref "abc" 1) ==> #\b
(substring "hello" 1 3) ==> "el"
(let ((s (make-string 3 #\x))) (string-set! s 1 #\y) s) ==> "xyx"
(string-append "ab" "cd" "e") ==> "abcde"
(string<? "abc" "abd") ==> #t
(string=? "ab" "ab" "ab") ==> #t
(string-copy "abc" 1) ==> "bc"
(symbol->string 'abc) ==> "abc"
(string->symbol "xyz") ==> xyz
(begin (write #\a) (display #\b) 'z) ==> #\abz
(vector-length #(1 2 3)) ==> 3
(vector->list #(1 2 3)) ==> (1 2 3)
(let ((v (make-vector 2000 0))) (let loop ((i 0)) (if (< i 2000) (begin (vector-set! v i i) (loop (+ i 1))))) (vector-ref v 1999)) ==> 1999
(equal? #(1 (2) "x") (vector 1 (list 2) "x")) ==> #t
(vector-ref #(1 2) 5) ==> index out of range
(bytevector 1 2 255) ==> #u8(1 2 255)
(bytevector-u8-ref #u8(5 6 7) 1) ==> 6
(let ((b (make-bytevector 2 0))) (bytevector-u8-set! b 0 9) b) ==> #u8(9 0)
(bytevector-length (make-bytevector 10 0)) ==> 10
(bytevector? #u8()) ==> #t
(utf8->string #u8(104 105)) ==> "hi"
(string->utf8 "AB") ==> #u8(65 66)
(let loop ((i 0) (s "")) (if (< i 3000) (loop (+ i 1) (string-append "ab" "cd")) (string-length s))) ==> 4
(let ((v (make-vector 100 1))) (let loop ((i 0)) (if (< i 3000) (begin (make-string 10 #\a) (loop (+ i 1))))) (vector-ref v 99)) ==> 1
; item 3: sqrt exact for exact squares, inexact otherwise; rounding on non-integers
(sqrt 1/4) ==> 1/2
(sqrt 16.0) ==> 4.0
(exact? (sqrt 2)) ==> #f
(< 1.4142 (sqrt 2) 1.4143) ==> #t
(floor -4.3) ==> -5.0
(ceiling -4.3) ==> -4.0
(truncate -4.3) ==> -4.0
(round -4.3) ==> -4.0
(floor 3.5) ==> 3.0
(ceiling 3.5) ==> 4.0
(truncate 3.5) ==> 3.0
(round 3.5) ==> 4.0
(round 2.5) ==> 2.0
(round 7/2) ==> 4
(round -7/2) ==> -4
(round 7/10) ==> 1
(floor -7/2) ==> -4
(ceiling -7/2) ==> -3
(truncate -7/2) ==> -3
(floor 5) ==> 5
; item 4: quasiquote, macros, promises, values, call/cc, dynamic-wind, exceptions, parameters, records
`(1 ,(+ 1 1) ,@(list 3 4)) ==> (1 2 3 4)
`(a b) ==> (a b)
(let ((x 5)) `(x ,x)) ==> (x 5)
(let ((xs '(1 2))) `(0 ,@xs 3 . 4)) ==> (0 1 2 3 . 4)
(define-syntax swap! (syntax-rules () ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
(let ((x 1) (y 2)) (swap! x y) (list x y)) ==> (2 1)
(define-syntax my-or (syntax-rules () ((_) #f) ((_ e) e) ((_ e r ...) (let ((t e)) (if t t (my-or r ...))))))
(my-or #f #f 3) ==> 3
(my-or) ==> #f
(define-syntax my-let* (syntax-rules () ((_ () body ...) (let () body ...)) ((_ ((x v) rest ...) body ...) (let ((x v)) (my-let* (rest ...) body ...)))))
(my-let* ((a 1) (b (+ a 1))) (* a b)) ==> 2
(define-syntax for (syntax-rules (in) ((_ x in lst body ...) (for-each (lambda (x) body ...) lst))))
(let ((s 0)) (for x in '(1 2 3) (set! s (+ s x))) s) ==> 6
(let-syntax ((foo (syntax-rules () ((_ x) (* x 10))))) (foo 4)) ==> 40
(force (delay (+ 1 2))) ==> 3
(define count 0) ==> count
(define pr (delay (begin (set! count (+ count 1)) count))) ==> pr
(list (force pr) (force pr)) ==> (1 1)
(promise? (make-promise 5)) ==> #t
(force (make-promise 5)) ==> 5
(force 7) ==> 7
(call-with-values (lambda () (values 1 2)) +) ==> 3
(call-with-values (lambda () 5) (lambda (x) (* x x))) ==> 25
(let-values (((a b) (values 1 2)) ((c) (values 3))) (list a b c)) ==> (1 2 3)
(let-values (((q r) (floor/ 7 2))) (list q r)) ==> (3 1)
(let-values (((q r) (truncate/ -7 2))) (list q r)) ==> (-3 -1)
(let-values (((s r) (exact-integer-sqrt 17))) (list s r)) ==> (4 1)
(define-values (dq dr) (floor/ 17 5)) ==> 
(list dq dr) ==> (3 2)
(call/cc (lambda (k) (+ 1 (k 42)))) ==> 42
(+ 1 (call-with-current-continuation (lambda (k) 2))) ==> 3
(call/cc (lambda (k) (for-each (lambda (x) (if (> x 2) (k x))) '(1 2 3 4)) 'none)) ==> 3
(let ((path '())) (dynamic-wind (lambda () (set! path (cons 'in path))) (lambda () (set! path (cons 'body path))) (lambda () (set! path (cons 'out path)))) (reverse path)) ==> (in body out)
(let ((path '())) (call/cc (lambda (k) (dynamic-wind (lambda () (set! path (cons 'in path))) (lambda () (k 'x)) (lambda () (set! path (cons 'out path)))))) (reverse path)) ==> (in out)
(guard (e (#t (list 'caught e))) (raise 'boom)) ==> (caught boom)
(guard (e ((symbol? e) 'sym) ((string? e) 'str)) (raise "x")) ==> str
(guard (e ((error-object? e) (error-object-message e))) (error "bad thing" 1 2)) ==> "bad thing"
(guard (e ((error-object? e) (error-object-irritants e))) (error "bad" 1 2)) ==> (1 2)
(with-exception-handler (lambda (e) 10) (lambda () (+ 1 (raise-continuable 'oops)))) ==> 11
(guard (e (#t 'outer)) (guard (e2 ((string? e2) 'inner)) (raise 'sym))) ==> outer
(guard (e (#t (list 'v e))) (+ 1 2)) ==> 3
(error "plain" 'x) ==> plain x
(define pa (make-parameter 10)) ==> pa
(pa) ==> 10
(parameterize ((pa 20)) (pa)) ==> 20
(pa) ==> 10
(define pb (make-parameter 5 (lambda (x) (* x 2)))) ==> pb
(pb) ==> 10
(parameterize ((pb 3)) (pb)) ==> 6
(define-record-type point (make-point x y) point? (x point-x set-point-x!) (y point-y))
(point-x (make-point 1 2)) ==> 1
(let ((p (make-point 1 2))) (set-point-x! p 9) (point-x p)) ==> 9
(point? (make-point 1 2)) ==> #t
(point? 5) ==> #f
(define cl (case-lambda ((x) 'one) ((x y) 'two) ((x . r) 'many))) ==> cl
(list (cl 1) (cl 1 2) (cl 1 2 3)) ==> (one two many)
; item 5: primitive errors are raisable error objects
(guard (e (#t 'caught)) (car 5)) ==> caught
(guard (e ((error-object? e) (error-object-message e))) (vector-ref (vector 1) 9)) ==> "index out of range"
(guard (e ((error-object? e) (list (error-object-message e) (error-object-irritants e)))) undefined-thing) ==> ("unbound variable" (undefined-thing))
(car 5) ==> not a pair
(quote (a ... b)) ==> (a ... b)
(quote (1 . 2)) ==> (1 . 2)
(length (quote (rest ...))) ==> 2
; item 6: primitives check their argument count
(car 1 2) ==> wrong number of arguments
(cons 1) ==> wrong number of arguments
(apply +) ==> wrong number of arguments
(vector-ref (vector 1)) ==> wrong number of arguments
(guard (e (#t (quote caught))) (car)) ==> caught
((lambda (x) x)) ==> too few arguments
; item 8: define returns an unspecified value; the REPL only echoes the name
(let ((v (begin (define dv 5)))) (eq? v (quote dv))) ==> #f
(begin (define dw 6)) ==>
(define dz 7) ==> dz
(define (dfn a) a) ==> dfn
