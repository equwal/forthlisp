; shim.scm -- maps the (chibi test) forms onto the chip Scheme. One form per line.
; test and test-assert are procedures here: they evaluate their arguments like the macros do,
; then print <<pass>> or <<fail VALUE>> for host.lisp to count.
(define (test-begin . o) #t)
(define (test-end . o) #t)
(define (%report ok got) (if ok (display "<<pass>>") (begin (display "<<fail ") (write got) (display ">>"))))
(define (test . args) (let ((expected (if (= (length args) 3) (cadr args) (car args))) (got (if (= (length args) 3) (caddr args) (cadr args)))) (%report (equal? expected got) got)))
(define (test-assert . args) (let ((got (car (reverse args)))) (%report (if got #t #f) got)))
(define-syntax test-error (syntax-rules () ((_ e) (%report (guard (c (#t #t)) e #f) 'no-error)) ((_ n e) (%report (guard (c (#t #t)) e #f) 'no-error))))
(define-syntax test-values (syntax-rules () ((_ x e) (test (call-with-values (lambda () x) list) (call-with-values (lambda () e) list))) ((_ n x e) (test (call-with-values (lambda () x) list) (call-with-values (lambda () e) list)))))
