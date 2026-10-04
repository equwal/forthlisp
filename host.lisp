;;; host.lisp -- host side: a Lisp-to-Forth compiler and a serial driver for the
;;; Mecrisp Forth that runs in QEMU. Run with: sbcl --script host.lisp <command>
;;;
;;;   compile FILE     print the Forth that FILE's defuns compile to
;;;   load             send lisp.fs and the compiled prims.lisp, enter the target REPL
;;;   demo             scripted transcript of all three layers
;;;   ktest [FILE]     run the kernel word tests (default forth-tests.txt) on a fresh chip
;;;   suite            run the vendored chibi-scheme R7RS suite (tests/r7rs/), write results.txt
;;;   test [FILE]      run the R7RS conformance subset (default r7rs-tests.scm) on the chip
;;;
;;; The compiler keeps every local on the Forth data stack and tracks the stack
;;; layout at compile time, so a variable reference becomes dup / over / n pick.

(require :sb-bsd-sockets)
(defpackage :lfl (:use :cl))
(in-package :lfl)

;;; ---------- compiler ----------

(defvar *out*)
(defvar *current* nil)
(defparameter *void-words* '(print cr)
  "Forth words that push nothing.")

(defun emit (&rest toks) (dolist (tok toks) (push tok *out*)))
(defun word (sym) (string-downcase (symbol-name sym)))

(defun compile-expr (x env)
  "Compile X with ENV, the compile-time stack top first (NIL marks a temporary).
Return T when the code leaves one value on the stack."
  (cond ((integerp x) (emit (princ-to-string x)) t)
        ((null x) (emit "0") t)
        ((symbolp x)
         (let ((n (position x env)))
           (case n
             ((nil) (emit (word x)) (not (member x *void-words*)))
             (0 (emit "dup") t)
             (1 (emit "over") t)
             (t (emit (format nil "~d pick" n)) t))))
        ((eq (car x) 'if)
         (destructuring-bind (c a b) (cdr x)
           (compile-expr c env) (emit "if") (compile-expr a env)
           (emit "else") (compile-expr b env) (emit "then") t))
        ((eq (car x) 'forth) (apply #'emit (cdr x)) t)
        (t (let ((e env))
             (dolist (a (cdr x))
               (unless (compile-expr a e) (error "~s pushes nothing" a))
               (push nil e)))
           (compile-expr (if (eq (car x) *current*) 'recurse (car x))
                         (make-list (length (cdr x)) :initial-element :arg)))))

(defun compile-defun (form)
  "(defun name (params) body...) -> one line of Forth."
  (destructuring-bind (name params &rest body) (cdr form)
    (let ((*current* name) (*out* nil) (env (reverse params)))
      (emit ":" (word name))
      (loop for (b . more) on body
            do (when (and (compile-expr b env) more) (emit "drop")))
      (loop repeat (length params) do (emit "nip"))
      (emit ";")
      (format nil "~{~a~^ ~}" (reverse *out*)))))

(defun compile-form (form)
  "Return the Forth lines for one top-level form."
  (ecase (car form)
    (defun (list (compile-defun form)))
    (defprims (loop for (name fw) in (cdr form)
                    collect (format nil "' ~a defprim ~a" (word fw) (word name))))))

(defun read-forms (path)
  (with-open-file (s path)
    (loop for f = (read s nil) while f collect f)))

(defun compile-file-to-forth (path)
  (mapcan #'compile-form (read-forms path)))

;;; ---------- serial transport (QEMU -serial tcp:127.0.0.1:PORT,server,nowait) ----------

(defvar *sock*)
(defvar *io*)
(defvar *log* t "Echo the conversation to stdout.")

(defun connect (&optional (port (parse-integer (or (sb-ext:posix-getenv "PORT") "4444"))))
  (loop repeat 150
        do (handler-case
               (let ((s (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp)))
                 (sb-bsd-sockets:socket-connect s #(127 0 0 1) port)
                 (setf *sock* s
                       *io* (sb-bsd-sockets:socket-make-stream
                             s :input t :output t :element-type 'character
                               :buffering :none :external-format :latin-1))
                 (return t))
             (sb-bsd-sockets:socket-error () (sleep 0.2)))
        finally (error "QEMU serial port ~d not reachable" port)))

(defun read-until (done-p timeout)
  "Read chars until (funcall done-p text) or TIMEOUT seconds. Return the text."
  (let ((acc (make-array 0 :element-type 'character :adjustable t :fill-pointer 0))
        (deadline (+ (get-internal-real-time) (* timeout internal-time-units-per-second)))
        (fd (sb-bsd-sockets:socket-file-descriptor *sock*)))
    (loop
      (when (funcall done-p acc) (return (remove #\Return acc)))
      (let ((left (/ (- deadline (get-internal-real-time)) internal-time-units-per-second)))
        (when (<= left 0) (error "timeout after ~as; target said: ~s" timeout acc))
        ;; Drain the stream's own buffer before sleeping on the fd.
        (let ((c (read-char-no-hang *io* nil :eof)))
          (cond ((eq c :eof) (error "serial connection closed"))
                (c (vector-push-extend c acc))
                (t (sb-sys:wait-until-fd-usable fd :input left))))))))

(defun ends-with (suffix s)
  (let ((n (length s)) (m (length suffix)))
    (and (>= n m) (string= suffix s :start2 (- n m)))))

(defun send (line)
  "Send LINE one char at a time, waiting for the target's echo of each. QEMU's USART
has a one-byte receive register and Mecrisp polls it, so a burst loses characters."
  (loop for c across line
        do (write-char c *io*) (finish-output *io*)
           (read-until (lambda (s) (find c s)) 2))
  (write-char #\Newline *io*) (finish-output *io*)
  (show line))

(defun show (text)
  (when *log* (write-string text) (finish-output)))

(defun forth (line &key (timeout 5))
  "Send one line to the Forth interpreter and wait for its ok."
  (send line)
  (let ((reply (read-until (lambda (s) (or (ends-with " ok." s)
                                           (search "not found." s)
                                           (search "Stack" s)))
                           timeout)))
    (show reply) (show (string #\Newline))
    (unless (ends-with " ok." reply) (error "Forth error: ~a" reply))
    (when (search "Redefine" reply) (error "~a: a word was redefined; later words may bind to the wrong one" reply))
    reply))

(defun comment-start (l)
  "Position of a Forth \\ comment word in L: a backslash at the start or after a space,
followed by a space or the end of the line. A backslash inside code (e.g. in .\" #\\\") stays."
  (loop for i from 0 below (length l)
        when (and (char= (char l i) #\\)
                  (or (zerop i) (char= (char l (1- i)) #\Space))
                  (or (= i (1- (length l))) (char= (char l (1+ i)) #\Space)))
          return i))

(defun forth-lines (lines)
  (dolist (l lines)
    (let ((l (string-trim " " (subseq l 0 (comment-start l)))))
      (unless (string= l "") (forth l)))))

(defun lisp-prompt (&key (timeout 5))
  "Read up to the target Lisp's prompt. Return the text before it."
  (let ((reply (read-until (lambda (s) (ends-with "> " s)) timeout)))
    (show reply)
    (string-trim '(#\Newline #\Space) (subseq reply 0 (- (length reply) 2)))))

(defun lisp-eval (expr &key (timeout 10))
  "Send EXPR to the target Lisp REPL. Return the printed result."
  (send expr)
  (lisp-prompt :timeout timeout))

;;; ---------- commands ----------

(defparameter *here* (directory-namestring (or *load-truename* "./")))
(defun here (name)
  "NAME relative to this file's directory, unless NAME is already absolute."
  (if (and (plusp (length name)) (char= (char name 0) #\/)) name (concatenate 'string *here* name)))

(defun load-target ()
  "Layer 2 + 3: send lisp.fs, then the Forth that prims.lisp compiles to."
  (forth "")
  (forth-lines (with-open-file (s (here "lisp.fs"))
                 (loop for l = (read-line s nil) while l collect l)))
  (forth-lines (compile-file-to-forth (here "prims.lisp")))
  (forth "unused ."))

(defun file-lines (name)
  "Lines of NAME that are not blank and not ; comments."
  (with-open-file (s (here name))
    (loop for l = (read-line s nil) while l
          for tl = (string-trim " " l)
          unless (or (string= tl "") (char= (char tl 0) #\;)) collect tl)))

(defun enter-lisp ()
  "Enter the chip REPL and load prelude.scm, one form per line."
  (send "lisp")
  (lisp-prompt)
  (let ((*log* nil))
    (dolist (l (file-lines "prelude.scm"))
      (let ((r (lisp-eval l)))
        (when (search "error" r) (error "prelude: ~a gave ~a" l r))))))

(defun ktest (name)
  "Layer 3: run NAME (lines of INPUT ==> OUTPUT) on a freshly booted kernel. Return failures."
  (let ((pass 0) (fail 0))
    (forth "")
    (with-open-file (s (here name))
      (loop for l = (read-line s nil) while l
            for tl = (string-trim " " l)
            unless (or (string= tl "") (char= (char tl 0) #\\))
              do (let* ((k (search "==>" tl))
                        (in (string-trim " " (subseq tl 0 k)))
                        (want (and k (string-trim " " (subseq tl (+ k 3))))))
                   (send in)
                   (let* ((r (read-until (lambda (s) (or (ends-with " ok." s) (search "not found." s)
                                                         (search "underflow" s)))
                                         10))
                          (r (string-trim '(#\Space #\Newline) (if (ends-with " ok." r) (subseq r 0 (- (length r) 4)) r))))
                     (if (or (null want) (string= r want))
                         (incf pass)
                         (progn (incf fail) (format t "~&FAIL ~a => ~s (want ~s)~%" in r want)))))))
    (format t "~&kernel tests: ~d passed, ~d failed, ~d total~%" pass fail (+ pass fail))
    fail))

(defun conformance (name)
  "Run NAME: lines of EXPR ==> WANT, compared as printed text. Return the failure count."
  (let ((pass 0) (fail 0))
    (dolist (l (file-lines name))
      (let* ((k (search "==>" l))
             (e (string-trim " " (subseq l 0 k)))
             (want (if k (string-trim " " (subseq l (+ k 3))) nil))
             (got (lisp-eval e)))
        (if (or (null want) (string= got want))
            (incf pass)
            (progn (incf fail) (format t "FAIL ~a => ~a (want ~a)~%" e got want)))))
    (format t "~%conformance: ~d passed, ~d failed, ~d total~%" pass fail (+ pass fail))
    fail))

(defun demo ()
  (connect)
  (format t "~%=== Layer 1: host Lisp compiles Lisp to Forth and runs it on the chip ===~%")
  (forth "")
  (dolist (line (compile-file-to-forth (here "demo.lisp")))
    (format t "[compiled] ~a~%" line)
    (forth line))
  (flet ((check (line want)
           (let ((r (forth line)))
             (unless (search want r) (error "layer 1: ~a gave ~a" line r)))))
    (check "7 sq ." "49") (check "10 fact ." "3628800"))
  (format t "~%=== Layer 2: load the Forth Lisp (core lisp.fs + prims compiled from prims.lisp) ===~%")
  (let ((*log* nil)) (load-target))
  (format t "~a~%" (forth "unused ."))
  (format t "~%=== Layer 3: Lisp (host) -> Forth (chip) -> Lisp (chip) ===~%")
  (enter-lisp)
  (let ((bad 0))
    (loop for (e want) in
          '(("(+ 1 2)" "3")
            ("(define (sq x) (* x x))" "sq")
            ("(sq 7)" "49")
            ("(define (fact n) (if (< n 2) 1 (* n (fact (- n 1)))))" "fact")
            ("(fact 7)" "5040")
            ("(cons 1 (cons 2 '()))" "(1 2)")
            ("(car '(a b c))" "a")
            ("(define (my-map f l) (if (null? l) '() (cons (f (car l)) (my-map f (cdr l)))))" "my-map")
            ("(my-map sq '(1 2 3 4))" "(1 4 9 16)")
            ("((lambda (x y) (- x y)) 10 3)" "7")
            ("(map fact '(1 2 3 4 5))" "(1 2 6 24 120)")
            ("(let loop ((i 0)) (if (< i 10000) (loop (+ i 1)) i))" "10000")
            ("(eq? (car '(a)) 'a)" "#t")
            ("(< 2 1)" "#f"))
          do (let ((v (lisp-eval e)))
               (format t "~a => ~a~a~%" e v (if (string= v want) "" (progn (incf bad) "   <-- WRONG")))))
    (send "(forth)") (forth "")
    (format t "(forth) => back at the Forth prompt~%")
    (format t "~a~%" (forth "unused ."))
    (if (zerop bad)
        (format t "~%SUCCESS: all three layers answered as expected.~%")
        (progn (format t "~%FAILED: ~d wrong answers.~%" bad) (sb-ext:exit :code 1)))))

(load (here "suite.lisp"))

(defun main (args)
  (let ((cmd (first args)))
    (cond ((equal cmd "compile")
           (format t "~{~a~%~}" (compile-file-to-forth (second args))))
          ((equal cmd "load")
           (connect) (load-target) (enter-lisp))
          ((equal cmd "demo") (demo))
          ((equal cmd "forth")
           (connect) (let ((*log* nil)) (load-target))
           (dolist (e (cdr args)) (forth e)))
          ((equal cmd "ktest")
           (connect)
           (let ((*log* nil)) (unless (zerop (ktest (or (second args) "forth-tests.txt"))) (sb-ext:exit :code 1))))
          ((equal cmd "suite")
           (connect) (let ((*log* nil)) (load-target) (enter-lisp))
           (run-suite "tests/r7rs/"))
          ((equal cmd "test")
           (connect) (let ((*log* nil)) (load-target) (enter-lisp))
           (unless (zerop (conformance (or (second args) "r7rs-tests.scm"))) (sb-ext:exit :code 1)))
          ((equal cmd "eval")
           (connect) (let ((*log* nil)) (load-target) (enter-lisp))
           (dolist (e (cdr args)) (format t "~a => ~a~%" e (lisp-eval e))))
          (t (format t "usage: host.lisp compile FILE | load | demo | ktest [FILE] | suite | test [FILE] | eval EXPR... | forth LINE...~%")))))

(handler-case (main (cdr sb-ext:*posix-argv*))
  (error (e) (format t "~&FAILED: ~a~%" e) (sb-ext:exit :code 1)))
