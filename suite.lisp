;;; suite.lisp -- run a vendored R7RS test suite (tests/r7rs/r7rs-tests.scm, chibi-scheme)
;;; on the chip. Loaded by host.lisp.
;;;
;;; The host splits the file into top-level forms and sends each one as a single line.
;;; tests/r7rs/shim.scm defines `test`, `test-assert`, test-begin and test-end on the chip
;;; as procedures that print <<pass>> or <<fail VALUE>>. tests/r7rs/skip.scm names what
;;; cannot run yet, with a reason. Every skipped test is counted. A form that fails before
;;; all of its tests have reported counts the missing ones as failures.

(in-package :lfl)

(defun split-forms (text)
  "Top-level data of TEXT as strings. Understands ; #| |# #; comments, strings, #\\ chars, |sym|."
  (let ((forms '()) (i 0) (n (length text)))
    (labels ((peek (k) (if (< (+ i k) n) (char text (+ i k)) #\Nul))
             (delim-p (c) (or (member c '(#\Space #\Tab #\Newline #\Return #\( #\) #\" #\;)) (char= c #\Nul)))
             (skip-ws ()
               (loop
                 (cond ((>= i n) (return))
                       ((member (peek 0) '(#\Space #\Tab #\Newline #\Return #\Page)) (incf i))
                       ((char= (peek 0) #\;) (loop until (or (>= i n) (char= (peek 0) #\Newline)) do (incf i)))
                       ((and (char= (peek 0) #\#) (char= (peek 1) #\|))
                        (incf i 2)
                        (let ((depth 1))
                          (loop while (and (< i n) (plusp depth))
                                do (cond ((and (char= (peek 0) #\|) (char= (peek 1) #\#)) (decf depth) (incf i 2))
                                         ((and (char= (peek 0) #\#) (char= (peek 1) #\|)) (incf depth) (incf i 2))
                                         (t (incf i))))))
                       ((and (char= (peek 0) #\#) (char= (peek 1) #\;)) (incf i 2) (skip-ws) (datum))
                       (t (return)))))
             (datum ()
               "Skip one datum starting at i."
               (let ((c (peek 0)))
                 (cond ((member c '(#\' #\` #\,))
                        (incf i) (when (char= (peek 0) #\@) (incf i)) (skip-ws) (datum))
                       ((char= c #\() (incf i)
                        (loop (skip-ws)
                              (cond ((>= i n) (return))
                                    ((char= (peek 0) #\)) (incf i) (return))
                                    (t (datum)))))
                       ((char= c #\)) (incf i))      ; stray close: consume
                       ((char= c #\") (incf i)
                        (loop until (or (>= i n) (char= (peek 0) #\"))
                              do (incf i (if (char= (peek 0) #\\) 2 1)))
                        (incf i))
                       ((char= c #\|) (incf i)
                        (loop until (or (>= i n) (char= (peek 0) #\|))
                              do (incf i (if (char= (peek 0) #\\) 2 1)))
                        (incf i))
                       ((and (char= c #\#) (char= (peek 1) #\\))
                        (incf i 3)                  ; #\ plus at least one character
                        (loop until (delim-p (peek 0)) do (incf i)))
                       ((and (char= c #\#) (member (peek 1) '(#\( )))
                        (incf i) (datum))
                       ((and (char= c #\#) (char-equal (peek 1) #\u) (char= (peek 2) #\8) (char= (peek 3) #\())
                        (incf i 3) (datum))
                       (t (loop until (delim-p (peek 0)) do (incf i)))))))
      (loop
        (skip-ws)
        (when (>= i n) (return))
        (let ((start i)) (datum) (push (subseq text start i) forms))))
    (nreverse forms)))

(defun one-line (form)
  "FORM on one line: newlines outside strings become spaces, inside strings \\n; comments dropped."
  (with-output-to-string (o)
    (let ((i 0) (n (length form)) (in-str nil) (prev-space nil))
      (loop while (< i n) do
        (let ((c (char form i)))
          (cond (in-str
                 (cond ((char= c #\\) (write-char c o) (incf i) (when (< i n) (write-char (char form i) o)))
                       ((char= c #\") (setf in-str nil) (write-char c o))
                       ((char= c #\Newline) (write-string "\\n" o))
                       (t (write-char c o))))
                ((and (char= c #\#) (< (1+ i) n) (char= (char form (1+ i)) #\\))
                 (write-string "#\\" o) (incf i 2) (when (< i n) (write-char (char form i) o)) (setf prev-space nil))
                ((char= c #\") (setf in-str t) (write-char c o) (setf prev-space nil))
                ((char= c #\;) (loop while (and (< i n) (char/= (char form i) #\Newline)) do (incf i)) (decf i))
                ((member c '(#\Space #\Tab #\Newline #\Return))
                 (unless prev-space (write-char #\Space o)) (setf prev-space t))
                (t (write-char c o) (setf prev-space nil))))
        (incf i)))))

(defparameter *test-heads* '("test" "test-assert" "test-error" "test-values" "test-numeric-syntax"
                             "test-precision" "test-read-error" "test-write-syntax"))

(defun form-head (form)
  (let* ((s (string-left-trim "(" (string-trim '(#\Space #\Newline) form)))
         (e (or (position-if (lambda (c) (member c '(#\Space #\Newline #\( #\)))) s) (length s))))
    (subseq s 0 e)))

(defun nested-tests (form)
  "Heads of the test calls inside FORM, in order."
  (let ((heads '()) (start 0))
    (loop
      (let ((p (search "(test" form :start2 start)))
        (unless p (return (nreverse heads)))
        (let ((h (form-head (subseq form p))))
          (when (member h *test-heads* :test #'string=) (push h heads)))
        (setf start (1+ p))))))

(defun read-skips (path)
  "skip.scm entries: (section NAME REASON) (head NAME REASON) (match SUBSTRING REASON)
(literal KIND REASON) (nonlatin1 \"\" REASON)."
  (with-open-file (s path)
    (let ((*read-eval* nil))
      (loop for e = (read s nil) while e
            collect (list (intern (string-upcase (symbol-name (first e))) :keyword) (second e) (third e))))))

(defun tokens (form)
  "Identifier-like tokens of FORM (a crude split on delimiters)."
  (let ((out '()) (start nil))
    (loop for i from 0 to (length form)
          for c = (if (< i (length form)) (char form i) #\Space)
          do (if (member c '(#\Space #\Newline #\Tab #\( #\) #\' #\"))
                 (when start (push (subseq form start i) out) (setf start nil))
                 (unless start (setf start i))))
    out))

(defun defined-names (form)
  "Names a skipped setup form would have defined: the name after define / define-syntax, or
every token of a define-record-type."
  (let ((head (form-head form)) (toks (reverse (tokens form))))
    (cond ((string= head "define-record-type")
           ;; type, constructor, predicate, and each field's accessor/modifier -- not field names
           (let ((f (handler-case (let ((*readtable* (copy-readtable nil)) (*read-eval* nil))
                                    (setf (readtable-case *readtable*) :preserve)
                                    (read-from-string form))
                      (error () nil))))
             (if (and (consp f) (>= (length f) 4))
                 (mapcar #'princ-to-string
                         (remove-if-not #'symbolp
                                        (append (list (second f) (if (consp (third f)) (first (third f)) (third f)) (fourth f))
                                                (loop for fld in (nthcdr 4 f) when (consp fld) append (cdr fld)))))
                 (cdr toks))))
          ((member head '("define" "define-syntax" "define-values") :test #'string=)
           (list (string-left-trim "(" (second toks))))
          (t '()))))

(defvar *skipped-names* '() "(name . reason) for definitions that were skipped.")

(defun literal-kind (tok)
  "Which number literal TOK is: :bignum (beyond 31 bits), :complex, :float, :ratio, :prefix, or NIL."
  (let ((digits (some #'digit-char-p tok)) (n (length tok)))
    (cond ((zerop n) nil)
          ((and (every (lambda (c) (or (digit-char-p c) (find c "+-"))) tok) digits
                (let ((v (ignore-errors (parse-integer tok)))) (and v (not (<= -1073741824 v 1073741823)))))
           :bignum)
          ((and (> n 1) (char= (char tok 0) #\#) (find (char-downcase (char tok 1)) "eixbod")) :prefix)
          ((member tok '("+inf.0" "-inf.0" "+nan.0" "-nan.0") :test #'string=) :float)
          ((and (char-equal (char tok (1- n)) #\i) (or digits (member tok '("+i" "-i") :test #'string=))
                (every (lambda (c) (or (digit-char-p c) (find (char-downcase c) "+-./eianf"))) tok))
           :complex)
          ((and digits (every (lambda (c) (or (digit-char-p c) (find c "+-/"))) tok) (find #\/ tok)
                (> (count-if #'digit-char-p tok) 1))
           :ratio)
          ((and digits (every (lambda (c) (or (digit-char-p c) (find (char-downcase c) "+-.e"))) tok)
                (or (find #\. tok) (find #\e tok)) (digit-char-p (char tok (if (find (char tok 0) "+-.") (min 1 (1- n)) 0))))
           :float)
          ((and (> n 1) (char= (char tok 0) #\.) (digit-char-p (char tok 1))) :float))))

(defun skip-reason (skips section form heads)
  (let ((toks (tokens form)))
    (dolist (sn *skipped-names*)
      (when (member (car sn) toks :test #'string=)
        (return-from skip-reason (format nil "uses ~a, skipped: ~a" (car sn) (cdr sn))))))
  (dolist (e skips)
    (destructuring-bind (kind what reason) e
      (when (ecase kind
              (:section (string= what section))
              (:head (or (string= what (form-head form)) (member what heads :test #'string=)))
              (:match (search what form))
              (:nonlatin1 (some (lambda (c) (> (char-code c) 255)) form))
              (:literal (some (lambda (tk) (eq (literal-kind tk) (intern (string-upcase what) :keyword)))
                              (tokens form))))
        (return reason)))))

(defun run-suite (dir)
  "Run DIR/r7rs-tests.scm with DIR/shim.scm and DIR/skip.scm. Write DIR/results.txt."
  (let* ((text (with-open-file (s (here (concatenate 'string dir "r7rs-tests.scm")) :external-format :utf-8)
                 (let ((str (make-string (file-length s)))) (subseq str 0 (read-sequence str s)))))
         (forms (split-forms text))
         (skips (read-skips (here (concatenate 'string dir "skip.scm"))))
         (section "") (pass 0) (fail 0) (skip 0) (setup-skipped 0)
         (reasons (make-hash-table :test 'equal)) (failures '()))
    (let ((*log* nil))
      (dolist (l (file-lines (concatenate 'string dir "shim.scm"))) (lisp-eval l)))
    (dolist (form forms)
      (let* ((head (form-head form)) (heads (nested-tests form)) (k (length heads)))
        (when (string= head "test-begin")
          (let ((q (position #\" form))) (when q (setf section (subseq form (1+ q) (position #\" form :start (1+ q)))))))
        (let ((reason (skip-reason skips section form heads)))
          (cond (reason
                 (when (zerop k)
                   (dolist (nm (defined-names form)) (push (cons nm reason) *skipped-names*)))
                 (if (zerop k) (incf setup-skipped) (incf skip k))
                 (incf (gethash reason reasons 0) (max k 0)))
                (t
                 (let* ((line (one-line form))
                        (out (handler-case (lisp-eval line :timeout 60)
                               (error (e) (format nil "HOST ERROR ~a" e))))
                        (p (count-substr "<<pass>>" out)))
                   (incf pass p)
                   (when (> k p)
                     (incf fail (- k p))
                     (push (format nil "[~a] ~a~%    => ~a" section
                                   (subseq line 0 (min 160 (length line)))
                                   (subseq out 0 (min 160 (length out))))
                           failures))
                   (when (search "HOST ERROR" out)
                     (let ((rest (reduce #'+ (mapcar (lambda (f) (length (nested-tests f)))
                                                     (cdr (member form forms))))))
                       (incf fail rest)
                       (push (format nil "ABORTED: the chip stopped answering; ~d later tests counted as failed" rest) failures))
                     (return))))))))
    (let ((total (+ pass fail skip)))
      (with-open-file (o (here (concatenate 'string dir "results.txt")) :direction :output :if-exists :supersede)
        (format o "r7rs suite: ~d passed, ~d failed, ~d skipped, ~d total~%" pass fail skip total)
        (format o "setup forms skipped: ~d~%~%skipped tests by reason:~%" setup-skipped)
        (maphash (lambda (r c) (format o "  ~4d  ~a~%" c r)) reasons)
        (format o "~%failures:~%~{~a~%~}" (reverse failures)))
      (format t "~&r7rs suite: ~d passed, ~d failed, ~d skipped, ~d total~%" pass fail skip total))))

(defun count-substr (sub s)
  (loop with start = 0 for p = (search sub s :start2 start) while p count t do (setf start (1+ p))))

(defun analyze (path)
  "Host only: list form heads and the longest one-line form."
  (let* ((text (with-open-file (s path :external-format :utf-8)
                 (let ((str (make-string (file-length s)))) (subseq str 0 (read-sequence str s)))))
         (forms (split-forms text)) (counts (make-hash-table :test 'equal)) (tests 0))
    (dolist (f forms)
      (incf (gethash (form-head f) counts 0))
      (incf tests (length (nested-tests f))))
    (format t "~d top-level forms, ~d test calls, longest line ~d~%" (length forms) tests
            (reduce #'max (mapcar (lambda (f) (length (one-line f))) forms)))
    (maphash (lambda (h c) (format t "  ~4d ~a~%" c h)) counts)))
