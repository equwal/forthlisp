;;; prims.lisp -- the chip Scheme's arithmetic and type primitives, in the host dialect.
;;; host.lisp compiles each defun to a Mecrisp Forth word and sends it to the chip, where
;;; lisp.fs registers it with defprim. A primitive takes its argument list (a chip list)
;;; and returns one tagged value. car cdr cons fix num bool pair? sym? proc? fixnum? err
;;; are words from lisp.fs; + - * / mod negate xor = < > are Forth.

;; Generic arithmetic: add2 sub2 mul2 div2 lt2 eq2 (lisp.fs) handle fixnums, rationals and
;; flonums. The accumulators here are tagged values: 1 is the fixnum 0, 3 is the fixnum 1.
(defun sum (l acc) (if (= l 0) acc (sum (cdr l) (add2 acc (car l)))))
(defun prod (l acc) (if (= l 0) acc (prod (cdr l) (mul2 acc (car l)))))
(defun diff (l acc) (if (= l 0) acc (diff (cdr l) (sub2 acc (car l)))))
(defun quo (l acc) (if (= l 0) acc (quo (cdr l) (div2 acc (car l)))))
(defun prim+ (a) (sum a 1))
(defun prim* (a) (prod a 3))
(defun prim- (a) (if (= (cdr a) 0) (sub2 1 (car a)) (diff (cdr a) (car a))))
(defun prim/ (a) (if (= (cdr a) 0) (div2 3 (car a)) (quo (cdr a) (car a))))
(defun divisor (a) (if (= (num (car (cdr a))) 0) (forth "s\" division by zero\" err") (num (car (cdr a)))))
(defun prim-quotient (a) (fix (/ (num (car a)) (divisor a))))
(defun prim-remainder (a) (fix (mod (num (car a)) (divisor a))))
(defun floored (r y) (if (if (= r 0) 0 (< (xor r y) 0)) (+ r y) r))
(defun prim-modulo (a) (fix (floored (mod (num (car a)) (divisor a)) (num (car (cdr a))))))

;; Comparison chains: (< 1 2 3) is #t. Each returns a Forth flag for bool.
(defun chain= (l) (if (= (cdr l) 0) -1 (if (eq2 (car l) (car (cdr l))) (chain= (cdr l)) 0)))
(defun chain< (l) (if (= (cdr l) 0) -1 (if (lt2 (car l) (car (cdr l))) (chain< (cdr l)) 0)))
(defun chain> (l) (if (= (cdr l) 0) -1 (if (lt2 (car (cdr l)) (car l)) (chain> (cdr l)) 0)))
(defun chain<= (l) (if (= (cdr l) 0) -1 (if (lt2 (car (cdr l)) (car l)) 0 (chain<= (cdr l)))))
(defun chain>= (l) (if (= (cdr l) 0) -1 (if (lt2 (car l) (car (cdr l))) 0 (chain>= (cdr l)))))
(defun prim= (a) (bool (chain= a)))
(defun prim< (a) (bool (chain< a)))
(defun prim> (a) (bool (chain> a)))
(defun prim<= (a) (bool (chain<= a)))
(defun prim>= (a) (bool (chain>= a)))

(defun prim-eq (a) (bool (= (car a) (car (cdr a)))))
(defun prim-car (a) (car (pair (car a))))
(defun prim-cdr (a) (cdr (pair (car a))))
(defun prim-cons (a) (cons (car a) (car (cdr a))))
(defun prim-null (a) (bool (= (car a) 0)))
(defun prim-pair (a) (bool (pair? (car a))))
(defun prim-symbol (a) (bool (sym? (car a))))
(defun prim-procedure (a) (bool (proc? (car a))))
(defun prim-boolean (a) (bool (if (= (car a) (forth "#t")) -1 (= (car a) (forth "#f")))))

;; (name forth-word): what defprim registers. Values are tagged words, so eq? and eqv? agree.
(defprims (+ prim+) (- prim-) (* prim*) (/ prim/) (quotient prim-quotient) (remainder prim-remainder)
          (modulo prim-modulo) (= prim=) (< prim<) (> prim>) (<= prim<=) (>= prim>=)
          (eq? prim-eq) (car prim-car) (cdr prim-cdr) (cons prim-cons)
          (null? prim-null) (pair? prim-pair) (symbol? prim-symbol)
          (procedure? prim-procedure) (boolean? prim-boolean))