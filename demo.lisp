;;; demo.lisp -- layer 1 input: host-dialect Lisp that host.lisp compiles to Forth words.
(defun sq (x) (* x x))
(defun fact (n) (if (< n 2) 1 (* n (fact (- n 1)))))
