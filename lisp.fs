\ lisp.fs -- an R7RS-small subset Scheme in Forth (our own kernel) for the STM32F446 (128 KiB RAM).
\ Values are 32-bit. Low 3 bits: xx1 fixnum (31-bit signed), 000 pair (0 is '()),
\ 010 symbol, 100 immediate (#f #t, unspecified, unbound, box tags, special-form markers,
\ characters), 110 procedure or box.
\ Pairs, symbols and procedures are 8-byte cells in `heap`: car word, cdr word.
\ Symbol: car = fixnum offset of its counted name in `names`, cdr = global value.
\ Procedure: car = fixnum primitive number, or a closure's parameters; closure cdr = (body . env).
\ Box: a 110 cell whose car is a box tag. Strings, vectors and bytevectors keep their contents
\ in a contiguous blob in `bheap`; the box's cdr holds the blob's data address. A blob header
\ names its one owner box, so the GC can slide live blobs down and fix the owner's cdr.
\ Rule: never hold a blob address across an allocation (cons, newbox); re-fetch it from the box.
\ A character is an immediate: (code+1) << 12 | 4.
\ An environment is an alist of (symbol . value) bindings in front of the globals.
\ GC: mark-sweep, run when cons finds the free list empty. Roots: the symbol list, plus
\ every word on the data and return stacks that looks like a heap reference (conservative).

49152 constant heapsize
heapsize buffer: heap
heapsize 64 / buffer: marks   \ one bit per 8-byte cell
16384 constant bsize   \ blob heap for strings, vectors, bytevectors
bsize buffer: bheap
0 variable btop
4096 constant namesize
namesize buffer: names
64 buffer: tok
128 cells buffer: prims
32 cells buffer: forms        \ special-form handlers
512 constant linesize   \ one REPL line; an expression may span lines
linesize buffer: lbuf
0 variable lpos  0 variable llen
0 variable free  0 variable ntop  0 variable syms  0 variable nprims  0 variable nforms
-1 variable pk
0 variable rsave  0 variable ssave
0 variable raw   \ 1 while display prints strings without quotes
0 variable 'eval  0 variable 'read  0 variable 'repl  0 variable 'print

4 constant #f  12 constant #t  20 constant unspec  28 constant unbound

: fixnum? ( v -- f ) 1 and 0<> ;
: sym? ( v -- f ) 7 and 2 = ;
: pair? ( v -- f ) dup 7 and 0= swap 0<> and ;
: special? ( v -- f ) dup 7 and 4 = swap dup 131 > swap 4096 < and and ;   \ forms: (k+16)*8+4
: char? ( v -- f ) dup 7 and 4 = swap 4095 > and ;
: mkchar ( code -- v ) 1+ 12 lshift 4 or ;
: charcode ( v -- code ) 12 rshift 1- ;
: fix ( n -- v ) 2* 1 or ;
: unfix ( v -- n ) 1 arshift ;
: addr ( v -- a ) 7 bic heap + ;
: car ( v -- v ) addr @ ;
: cdr ( v -- v ) addr cell+ @ ;
: car! ( v p -- ) addr ! ;
: cdr! ( v p -- ) addr cell+ ! ;
36 constant strtag  44 constant vectag  68 constant bvtag
: box? ( v tag -- f ) over 7 and 6 = if swap car = else 2drop false then ;
: proc? ( v -- f ) dup 7 and 6 = if car 7 and 4 <> else drop false then ;  \ boxes have an immediate tag in car
: truth ( v -- f ) #f <> ;
: bool ( f -- v ) if #t else #f then ;
: (eval) 'eval @ execute ;  : (read) 'read @ execute ;  : (print) 'print @ execute ;

: err ( addr len -- ) type cr  rsave @ 0= if quit then
  1 lpos ! 0 llen ! -1 pk !  ssave @ sp! rsave @ rp! 'repl @ execute ;
: pair ( v -- v ) dup pair? 0= if s" not a pair" err then ;
: num ( v -- n ) dup fixnum? 0= if s" not a number" err then unfix ;

\ --- garbage collector ---
: mbit ( v -- addr mask ) 3 rshift dup 3 rshift marks + swap 7 and 1 swap lshift ;
: marked? ( v -- f ) 7 bic mbit swap c@ and 0<> ;
: ref? ( w -- f )  \ tag 000, 010 or 110 and inside the heap
  dup 7 and dup 4 = swap 1 and or 0= swap 7 bic dup 7 > swap heapsize u< and and ;
: mark ( v -- ) begin dup ref? while
    dup marked? if drop exit then dup 7 bic mbit swap cbis!
    dup vectag box? if dup cdr ?dup if dup 4 - @ 2 rshift 0 ?do dup i cells + @ recurse loop drop then then
    dup car recurse cdr repeat drop ;
: scan ( hi lo -- ) begin 2dup u> while dup @ mark cell+ repeat 2drop ;
: sweep 0 free ! heapsize 8 - begin dup 7 > while
    dup marked? 0= if free @ over heap + ! dup free ! then 8 - repeat drop ;
0 variable bsrc  0 variable bdst
: blive? ( hdr -- f ) dup @ dup marked? if cdr swap 8 + = else 2drop false then ;
: bcompact  \ slide live blobs down, fix each owner's data address
  0 bsrc ! 0 bdst !
  begin bsrc @ btop @ < while
    bheap bsrc @ + dup 4 + @ aligned 8 +
    over blive? if
      over bheap bdst @ + 2 pick move
      bheap bdst @ + dup 8 + swap @ cdr!
      dup bdst +!
    then nip bsrc +!
  repeat bdst @ btop ! ;
: gc marks heapsize 64 / 0 fill  syms @ mark
  rsave @ if ssave @ sp@ scan  rsave @ rp@ scan then sweep bcompact ;
: cons ( a d -- p ) free @ 0= if gc free @ 0= if s" out of memory" err then then
  free @ dup car free !  tuck cdr! tuck car! ;
: balloc ( n box -- ) over aligned 8 + dup btop @ + bsize > if gc dup btop @ + bsize > if
    s" out of memory" err then then
  bheap btop @ + >r btop +! dup r@ ! over r@ 4 + ! r@ 8 + rot 0 fill r> 8 + swap cdr! ;
: newbox ( n tag -- box ) 0 cons 6 or tuck balloc ;
: blen ( box -- n ) cdr 4 - @ ;
: bdat ( box -- addr ) cdr ;
: chk ( v tag -- v ) over over box? 0= if s" wrong type" err then drop ;
: listlen ( list -- n ) 0 swap begin dup pair? while swap 1+ swap cdr repeat drop ;
: l>s ( list -- str ) dup listlen strtag newbox swap 0 swap begin dup pair? while
    dup car charcode 3 pick bdat 3 pick + c! swap 1+ swap cdr repeat 2drop ;
: l>bv ( list -- bv ) dup listlen bvtag newbox swap 0 swap begin dup pair? while
    dup car unfix 3 pick bdat 3 pick + c! swap 1+ swap cdr repeat 2drop ;
: l>v ( list -- vec ) dup listlen cells vectag newbox swap 0 swap begin dup pair? while
    dup car 3 pick bdat 3 pick cells + ! swap 1+ swap cdr repeat 2drop ;

\ --- symbols ---
: name ( sym -- addr len ) car unfix names + count ;
: intern ( addr len -- sym )
  syms @ begin dup while
    >r 2dup r@ car name compare if 2drop r> car exit then r> cdr
  repeat drop
  ntop @ over + 1+ namesize > if s" symbol space full" err then
  ntop @ >r  dup r@ names + c!  dup 1+ ntop +!  r@ names + 1+ swap move
  r> fix unbound cons 2 or  dup syms @ cons syms ! ;

0 ntop ! 0 syms ! 0 nprims ! 0 nforms ! gc
token quote intern constant s-quote
token else intern constant s-else
token => intern constant s-=>

\ --- numbers: 31-bit fixnums (overflow is an error), exact rationals, single-precision flonums ---
\ A rational is a 110 cell: car rattag, cdr (numerator . denominator), normalized, denominator > 1.
\ A flonum is a 110 cell: car flotag, cdr the IEEE-754 single bits (the kernel's FPU words).
52 constant rattag  60 constant flotag
: rat? ( v -- f ) rattag box? ;
: flo? ( v -- f ) flotag box? ;
: numeric? ( v -- f ) dup fixnum? over rat? or swap flo? or ;
: ovf s" overflow" err ;
: fits? ( n -- f ) dup 1073741823 > swap -1073741824 < or 0= ;
: >fix ( n -- v ) dup fits? 0= if ovf then fix ;
: *c ( a b -- n ) m* over 0< if 1+ then if ovf then dup fits? 0= if ovf then ;
: +c ( a b -- n ) + dup fits? 0= if ovf then ;
: -c ( a b -- n ) - dup fits? 0= if ovf then ;
: flo ( bits -- v ) flotag swap cons 6 or ;
: gcd ( a b -- g ) abs swap abs begin dup while tuck mod repeat drop ;
: mkrat ( n d -- v ) dup 0= if s" division by zero" err then
  dup 0< if negate swap negate swap then
  2dup gcd tuck / >r / r>
  dup 1 = if drop >fix exit then
  >r >fix r> >fix cons rattag swap cons 6 or ;
: numden ( v -- n d ) dup fixnum? if unfix 1 exit then
  dup rat? if cdr dup car unfix swap cdr unfix exit then s" not an exact number" err ;
0 variable n1  0 variable d1  0 variable n2  0 variable d2
: nd2 ( a b -- ) numden d2 ! n2 ! numden d1 ! n1 ! ;
: >float ( v -- bits ) dup fixnum? if unfix s>f exit then dup flo? if cdr exit then
  dup rat? if cdr dup car unfix s>f swap cdr unfix s>f f/ exit then s" not a number" err ;
: inex? ( a b -- f ) flo? swap flo? or ;
: fl2 ( a b -- af bf ) >float swap >float swap ;
: add2 ( a b -- v ) 2dup inex? if fl2 f+ flo exit then
  2dup and 1 and if unfix swap unfix +c fix exit then
  nd2 n1 @ d2 @ *c n2 @ d1 @ *c +c d1 @ d2 @ *c mkrat ;
: sub2 ( a b -- v ) 2dup inex? if fl2 f- flo exit then
  2dup and 1 and if unfix swap unfix swap -c fix exit then
  nd2 n1 @ d2 @ *c n2 @ d1 @ *c -c d1 @ d2 @ *c mkrat ;
: mul2 ( a b -- v ) 2dup inex? if fl2 f* flo exit then
  2dup and 1 and if unfix swap unfix *c fix exit then
  nd2 n1 @ n2 @ *c d1 @ d2 @ *c mkrat ;
: div2 ( a b -- v ) 2dup inex? if fl2 f/ flo exit then
  nd2 n2 @ 0= if s" division by zero" err then n1 @ d2 @ *c d1 @ n2 @ *c mkrat ;
: lt2 ( a b -- f ) 2dup inex? if fl2 f< exit then
  2dup and 1 and if < exit then nd2 n1 @ d2 @ *c n2 @ d1 @ *c < ;
: eq2 ( a b -- f ) 2dup inex? if fl2 f= exit then nd2 n1 @ n2 @ = d1 @ d2 @ = and ;
: eqv ( a b -- f ) 2dup = if 2drop true exit then
  2dup flo? swap flo? and if cdr swap cdr = exit then
  2dup rat? swap rat? and if cdr swap cdr 2dup car swap car = >r cdr swap cdr = r> and exit then
  2drop false ;
: fint? ( bits -- f ) dup 23 rshift 255 and dup 255 = if 2drop false exit then
  150 >= if drop true exit then dup f>s s>f f= ;
: fexact ( bits -- v ) dup $7F800000 and $7F800000 = if s" no exact representation" err then
  1 swap begin dup fint? 0= while $40000000 f* swap 2* swap over 1073741824 u> if ovf then repeat
  dup $7FFFFFFF and $4E800000 f< 0= if ovf then f>s swap mkrat ;
: exact ( v -- v ) dup flo? if cdr fexact exit then dup numeric? 0= if s" not a number" err then ;
: inexact ( v -- v ) dup flo? if exit then >float flo ;

\ --- reader: lines come from the kernel's accept, which handles BS and DEL ---
: refill lbuf linesize accept llen ! 0 lpos ! cr ;
: getc ( -- c ) pk @ dup 0< 0= if -1 pk ! exit then drop
  lpos @ llen @ > if refill then
  lpos @ llen @ = if 1 lpos +! 10 exit then
  lbuf lpos @ + c@ 1 lpos +! ;
: skipws begin getc dup 59 = if drop begin getc 10 = until 32 then dup 33 < while drop repeat pk ! ;
: delim? ( c -- f ) dup 33 < over 40 = or over 41 = or swap 59 = or ;
: rdtok ( n -- addr len ) begin getc dup delim? 0= while
    over 63 < if over tok + c! 1+ else drop then repeat pk ! tok swap ;
: digits ( addr len -- u true | false ) dup 0= if 2drop false exit then
  0 -rot over + swap do dup 107374182 > if drop false unloop exit then
    10 * i c@ 48 - dup 9 u> if 2drop false unloop exit then + loop true ;
: num? ( addr len -- v true | false )
  over c@ 45 = if swap 1+ swap 1- digits if negate >fix true else false then exit then
  over c@ 43 = if swap 1+ swap 1- then digits if >fix true else false then ;
0 variable fm  0 variable fe  0 variable fsaw  0 variable fneg  0 variable fpt
: dig? ( c -- f ) 48 - 10 u< ;
: /1 ( a n -- a+1 n-1 ) swap 1+ swap 1- ;
: adddig ( d -- ) s>f fm @ $41200000 f* f+ fm ! ;
: rdflo ( addr len -- v true | false )
  2dup s" +inf.0" compare if 2drop $7F800000 flo true exit then
  2dup s" -inf.0" compare if 2drop $FF800000 flo true exit then
  2dup s" +nan.0" compare if 2drop $7FC00000 flo true exit then
  0 fm ! 0 fe ! 0 fsaw ! 0 fneg ! 0 fpt !
  over c@ 45 = if -1 fneg ! /1 else over c@ 43 = if /1 then then
  begin dup if over c@ dig? else 0 then while over c@ 48 - adddig -1 fsaw ! /1 repeat
  dup if over c@ 46 = if -1 fpt ! /1
    begin dup if over c@ dig? else 0 then while over c@ 48 - adddig -1 fe +! -1 fsaw ! /1 repeat then then
  fsaw @ 0= if 2drop false exit then
  dup if over c@ 32 or 101 = if -1 fpt ! /1 num? 0= if false exit then unfix fe +! 0 0
    else 2drop false exit then then
  2drop fpt @ 0= if ovf then  \ only digits, yet num? refused it: too big for a fixnum
  fm @ fe @ dup 0< if negate 0 ?do $41200000 f/ loop else 0 ?do $41200000 f* loop then
  fneg @ if $80000000 or then flo true ;
: slash ( addr len -- i | -1 ) 0 begin 2dup > while 2 pick over + c@ 47 = if nip nip exit then 1+ repeat 2drop drop -1 ;
: rdrat ( addr len -- v true | false ) 2dup slash dup 0< if drop 2drop false exit then
  >r over r@ num? 0= if rdrop 2drop false exit then
  -rot swap r@ 1+ + swap r> 1+ - digits 0= if drop false exit then
  swap unfix swap mkrat true ;
: atom ( addr len -- v ) 2dup num? if nip nip exit then
  2dup rdrat if nip nip exit then  2dup rdflo if nip nip exit then
  2dup s" #t" compare if 2drop #t exit then  2dup s" #true" compare if 2drop #t exit then
  2dup s" #f" compare if 2drop #f exit then  2dup s" #false" compare if 2drop #f exit then
  intern ;
: rdstr ( -- list ) getc dup 34 = if drop 0 exit then
  dup 92 = if drop getc dup 110 = if drop 10 then dup 116 = if drop 9 then then
  mkchar recurse cons ;
: cname ( addr len -- code | -1 )
  2dup s" space" compare if 2drop 32 exit then  2dup s" newline" compare if 2drop 10 exit then
  2dup s" tab" compare if 2drop 9 exit then  2dup s" null" compare if 2drop 0 exit then
  2dup s" alarm" compare if 2drop 7 exit then  2dup s" backspace" compare if 2drop 8 exit then
  2dup s" delete" compare if 2drop 127 exit then  2dup s" escape" compare if 2drop 27 exit then
  2dup s" return" compare if 2drop 13 exit then
  over c@ 120 = if base @ >r 16 base ! /1 number r> base ! if exit then -1 exit then
  2drop -1 ;
: rdchar ( -- v ) getc tok c! 1 rdtok dup 1 = if drop c@ mkchar exit then
  cname dup 0< if drop s" bad character name" err then mkchar ;
: rdlist ( -- list ) skipws getc
  dup 41 = if drop 0 exit then
  dup 46 = if drop (read) skipws getc drop exit then
  pk ! (read) recurse cons ;
: read ( -- v ) skipws getc
  dup 40 = if drop rdlist exit then
  dup 39 = if drop s-quote recurse 0 cons cons exit then
  dup 41 = if drop s" unexpected )" err then
  dup 34 = if drop rdstr l>s exit then
  dup 35 = if drop getc dup 40 = if drop rdlist l>v exit then
    dup 92 = if drop rdchar exit then
    dup 117 = if drop getc drop getc drop rdlist l>bv exit then   \ #u8(
    pk ! 35 tok c! 1 rdtok atom exit then
  pk ! 0 rdtok atom ;
' read 'read !

\ --- printer ---
: pint ( n -- ) dup 0< if 45 emit negate then 0 <# #s #> type ;
: pdigits ( E addr len -- ) rot dup -5 < over 9 > or if
    >r over c@ emit 46 emit 1- swap 1+ swap dup if type else 2drop 48 emit then 101 emit r> pint exit then
  dup 0< if ." 0." negate 1- 0 ?do 48 emit loop type exit then
  1+ 2dup < if over - >r type r> 0 ?do 48 emit loop ." .0" exit then
  >r over r@ type swap r@ + swap r> - 46 emit dup if type else 2drop 48 emit then ;
: pflo ( bits -- ) \ ponytail: 7 significant digits from float scaling; the last digit can be off by one,
  \ so output need not read back to the same float. Shortest round-trip printing needs 64-bit digit generation.
  dup $7F800000 and $7F800000 = if dup $7FFFFF and if drop ." +nan.0" exit then
    0< if ." -inf.0" else ." +inf.0" then exit then
  dup 0< if 45 emit $7FFFFFFF and then
  dup 0= if drop ." 0.0" exit then
  0 swap begin dup $4B189680 f< 0= while $41200000 f/ swap 1+ swap repeat
  begin dup $49742400 f< while $41200000 f* swap 1- swap repeat
  $3F000000 f+ f>s dup 9999999 > if 10 / swap 1+ swap then
  swap 6 + swap 0 <# #s #>
  begin dup 1 > if 2dup + 1- c@ 48 = else 0 then while 1- repeat pdigits ;
: pnum ( v -- ) unfix pint ;
: pchar ( v -- ) charcode raw @ if emit exit then ." #\"
  dup 32 = if drop ." space" exit then  dup 10 = if drop ." newline" exit then
  dup 9 = if drop ." tab" exit then  dup 0= if drop ." null" exit then emit ;
: pstr ( box -- ) raw @ if dup bdat swap blen type exit then
  34 emit dup blen 0 ?do dup bdat i + c@
    dup 34 = over 92 = or if 92 emit then dup 10 = if drop 92 emit 110 emit else emit then loop drop 34 emit ;
: pvec ( box -- ) ." #(" dup blen 2 rshift 0 ?do i if space then dup bdat i cells + @ (print) loop drop 41 emit ;
: pbv ( box -- ) ." #u8(" dup blen 0 ?do i if space then dup bdat i + c@ pint loop drop 41 emit ;
: print ( v -- )
  dup fixnum? if pnum exit then
  dup 0= if drop ." ()" exit then
  dup sym? if name type exit then
  dup #t = if drop ." #t" exit then
  dup #f = if drop ." #f" exit then
  dup char? if pchar exit then
  dup strtag box? if pstr exit then
  dup vectag box? if pvec exit then
  dup bvtag box? if pbv exit then
  dup rat? if cdr dup car pnum 47 emit cdr pnum exit then
  dup flo? if cdr pflo exit then
  dup proc? if drop ." #<procedure>" exit then
  dup special? if drop ." #<syntax>" exit then
  dup pair? 0= if drop exit then
  40 emit begin dup car recurse cdr
    dup 0= if drop 41 emit exit then
    dup pair? 0= if ."  . " recurse 41 emit exit then space again ;
' print 'print !

\ --- environments ---
: where ( sym env -- binding | 0 )
  begin dup while 2dup car car = if nip car exit then cdr repeat 2drop 0 ;
: lookup ( sym env -- v ) over swap where ?dup if nip cdr exit then
  dup cdr dup unbound <> if nip exit then drop ." unbound variable: " name type s"  " err ;
: frame ( env -- env' ) #f #f cons swap cons ;   \ a dummy binding that internal defines can follow
: bind ( params args env -- env' )
  begin 2 pick pair? while over pair? 0= if s" too few arguments" err then
    2 pick car 2 pick car cons swap cons  rot cdr rot cdr rot repeat
  rot dup 0= if drop swap if s" too many arguments" err then exit then
  rot cons swap cons ;
: def-bind ( val sym env -- ) dup 0= if drop cdr! exit then
  >r swap cons r@ car r@ cdr cons r@ cdr! r> car! ;
: closure ( params body env -- proc ) cons cons 6 or ;
: evlis ( list env -- list' ) over 0= if drop exit then
  over car over (eval) >r swap cdr swap recurse r> swap cons ;

\ --- eval: handlers return ( x env 0 ) for a tail call or ( v -1 ) for a value ---
: seq ( body env -- x env 0 | v -1 ) over 0= if 2drop unspec -1 exit then
  begin over cdr while over car over (eval) drop swap cdr swap repeat swap car swap 0 ;
: applyc ( f args -- x env 0 | v -1 )
  over proc? 0= if s" not a procedure" err then
  over car fixnum? if swap car unfix cells prims + @ execute -1 exit then
  over car swap rot cdr dup >r cdr frame bind r> car swap seq ;
: apply ( f args -- v ) applyc if exit then (eval) ;
: eval ( x env -- v )
  begin
    rp@ rsave @ 3500 - u<  sp@ ssave @ 3500 - u< or if s" too deep" err then  \ 4 KiB stacks
    over sym? if lookup exit then
    over pair? 0= if drop exit then
    over car over recurse
    dup special? if 3 rshift 16 - cells forms + @ execute
    else -rot swap cdr swap evlis applyc then
  until ;
' eval 'eval !

: defform ( xt "name" -- ) nforms @ cells forms + !
  nforms @ 16 + 3 lshift 4 or  token intern cdr!  1 nforms +! ;

: f-quote ( x env ) drop cdr car -1 ;
: f-if ( x env ) >r cdr dup car r@ (eval) truth if cdr car else cdr cdr dup if car else drop unspec then then r> 0 ;
: f-lambda ( x env ) >r cdr dup car swap cdr r> closure -1 ;
: f-begin ( x env ) swap cdr swap seq ;
: f-define ( x env ) swap cdr dup car sym? if
    dup car >r cdr car over (eval) r@ rot def-bind r> -1 exit then
  dup car car >r dup car cdr swap cdr 2 pick closure r@ rot def-bind r> -1 ;
: f-set ( x env ) swap cdr dup car >r cdr car over (eval) swap r@ swap where
  ?dup if cdr! else r@ cdr! then rdrop unspec -1 ;
: lbind ( binds env eenv -- env' )  \ evaluate each (name expr) in eenv, bind onto env
  begin 2 pick while 2 pick car dup car swap cdr car 2 pick (eval) cons
    rot cons swap rot cdr -rot repeat drop nip ;
: lbind* ( binds env -- env' ) begin over while
    over car dup car swap cdr car 2 pick (eval) cons swap cons swap cdr swap repeat nip ;
: cars ( list -- list' ) dup 0= if exit then dup car car swap cdr recurse cons ;
: evargs ( binds env -- vals ) over 0= if drop exit then
  over car cdr car over (eval) >r swap cdr swap recurse r> swap cons ;
: namedlet ( env rest -- x env 0 )
  dup cdr car 2 pick evargs >r
  dup car unbound cons >r
  swap frame r@ swap cons
  over cdr car cars rot cdr cdr 2 pick closure
  dup r> cdr! nip r> applyc ;
: f-let ( x env ) swap cdr dup car sym? if namedlet exit then
  dup car rot dup frame swap lbind swap cdr swap seq ;
: f-let* ( x env ) swap cdr dup car rot frame lbind* swap cdr swap seq ;
: prebind ( binds env -- env' ) begin over while over car car unbound cons swap cons swap cdr swap repeat nip ;
: setall ( binds env -- ) begin over while
    over car cdr car over (eval) 2 pick car car 2 pick where cdr! swap cdr swap repeat 2drop ;
: f-letrec ( x env ) swap cdr dup car rot frame over swap prebind tuck setall swap cdr swap seq ;
: f-cond ( x env ) swap cdr begin dup while
    dup car car s-else = if car cdr swap seq exit then
    dup car car 2 pick (eval) dup truth if
      swap car cdr dup 0= if drop nip -1 exit then
      dup car s-=> = if cdr car 2 pick (eval) rot drop swap 0 cons applyc exit then
      nip swap seq exit then
    drop cdr repeat 2drop unspec -1 ;
: memq ( v list -- f ) begin dup pair? while 2dup car = if 2drop true exit then cdr repeat 2drop false ;
: f-case ( x env ) swap cdr dup car 2 pick (eval) swap cdr begin dup while
    dup car car dup s-else = swap 3 pick swap memq or if
      car cdr dup car s-=> = if cdr car 2 pick (eval) rot drop swap 0 cons applyc exit then
      nip swap seq exit then
    cdr repeat drop 2drop unspec -1 ;
: f-and ( x env ) swap cdr dup 0= if 2drop #t -1 exit then
  begin dup cdr while dup car 2 pick (eval) truth 0= if 2drop #f -1 exit then cdr repeat car swap 0 ;
: f-or ( x env ) swap cdr dup 0= if 2drop #f -1 exit then
  begin dup cdr while dup car 2 pick (eval) dup truth if nip nip -1 exit then drop cdr repeat car swap 0 ;
: f-when ( x env ) >r cdr dup car r@ (eval) truth if cdr r> seq else drop rdrop unspec -1 then ;
: f-unless ( x env ) >r cdr dup car r@ (eval) truth if drop rdrop unspec -1 else cdr r> seq then ;
: seqall ( body env -- ) begin over while over car over (eval) drop swap cdr swap repeat 2drop ;
: stepvals ( vars env -- vals ) over 0= if drop exit then
  over car cdr cdr dup if car over (eval) else drop over car car over lookup then
  >r swap cdr swap recurse r> swap cons ;
: f-do ( x env ) swap cdr swap  over car over dup frame swap lbind
  begin 2 pick cdr car car over (eval) truth 0= while
    2 pick cdr cdr over seqall
    2 pick car over stepvals nip 2 pick car cars swap 2 pick frame bind
  repeat nip swap cdr car cdr swap seq ;

' f-quote defform quote   ' f-if defform if   ' f-lambda defform lambda
' f-begin defform begin   ' f-define defform define   ' f-set defform set!
' f-let defform let   ' f-let* defform let*   ' f-letrec defform letrec
' f-letrec defform letrec*   ' f-cond defform cond   ' f-case defform case
' f-and defform and   ' f-or defform or   ' f-when defform when
' f-unless defform unless   ' f-do defform do

\ --- primitives written in Forth; prims.lisp adds the rest ---
: defprim ( xt "name" -- ) token intern >r nprims @ dup 1+ nprims !
  tuck cells prims + ! fix 0 cons 6 or r> cdr! ;
: spread ( list -- list' ) dup cdr 0= if car exit then dup car swap cdr recurse cons ;
: p-apply ( args -- v ) dup car swap cdr spread apply ;
: p-display ( args -- v ) 1 raw ! car print 0 raw ! unspec ;
: p-write ( args -- v ) car print unspec ;
0 variable fsz
: arg2 ( args -- a b ) dup car swap cdr car ;
: arg3 ( args -- a b c ) dup car swap cdr dup car swap cdr car ;
: ix ( box i size -- addr ) >r over blen r@ / over u> 0= if s" index out of range" err then r> * swap bdat + ;
: range ( box s e size -- box s e ) >r 2dup > if s" bad range" err then
  over 0< if s" bad range" err then 2 pick blen r> / over < if s" bad range" err then ;
: p-string? ( args -- v ) car strtag box? bool ;
: p-vector? ( args -- v ) car vectag box? bool ;
: p-bv? ( args -- v ) car bvtag box? bool ;
: p-char? ( args -- v ) car char? bool ;
: p-c>i ( args -- v ) car dup char? 0= if s" not a character" err then charcode fix ;
: p-i>c ( args -- v ) car num mkchar ;
: p-slen ( args -- v ) car strtag chk blen fix ;
: p-vlen ( args -- v ) car vectag chk blen 2 rshift fix ;
: p-bvlen ( args -- v ) car bvtag chk blen fix ;
: p-sref ( args -- v ) arg2 num swap strtag chk swap 1 ix c@ mkchar ;
: p-sset ( args -- v ) arg3 charcode >r num swap strtag chk swap 1 ix r> swap c! unspec ;
: p-vref ( args -- v ) arg2 num swap vectag chk swap 4 ix @ ;
: p-vset ( args -- v ) arg3 >r num swap vectag chk swap 4 ix r> swap ! unspec ;
: p-bvref ( args -- v ) arg2 num swap bvtag chk swap 1 ix c@ fix ;
: p-bvset ( args -- v ) arg3 num >r num swap bvtag chk swap 1 ix r> swap c! unspec ;
: fillbox ( k tag c size -- box ) \ a new box of k elements, each c; c stays on the stack (a GC root)
  fsz ! -rot over fsz @ * swap newbox swap 0 ?do
    dup bdat i fsz @ * + 2 pick fsz @ 1 = if swap c! else swap ! then loop nip ;
: opt ( args default -- x ) over cdr if drop cdr car else nip then ;
: p-mkstr ( args -- v ) dup car num swap 32 mkchar opt charcode strtag swap 1 fillbox ;
: p-mkvec ( args -- v ) dup car num swap #f opt vectag swap 4 fillbox ;
: p-mkbv ( args -- v ) dup car num swap 1 opt unfix bvtag swap 1 fillbox ;
: >list ( box s e size -- list ) \ elements s..e-1 as a list: chars, values or byte fixnums
  >r 0 swap begin 2 pick over < while 1-
    3 pick bdat over r@ * + r@ 1 = if c@ else @ then
    4 pick strtag box? if mkchar else 4 pick bvtag box? if fix then then
    rot cons swap repeat drop nip nip rdrop ;
: p-s>l ( args -- v ) arg3 num >r num r> 2 pick strtag chk drop 1 range 1 >list ;
: p-v>l ( args -- v ) arg3 num >r num r> 2 pick vectag chk drop 4 range 4 >list ;
: p-bv>l ( args -- v ) car bvtag chk 0 over blen 1 >list ;
: p-l>s ( args -- v ) car l>s ;
: p-l>v ( args -- v ) car l>v ;
: p-l>bv ( args -- v ) car l>bv ;
: ssub ( box s e -- str ) 1 range over - dup strtag newbox >r rot bdat rot + r@ bdat rot move r> ;
: p-substr ( args -- v ) arg3 num >r num r> 2 pick strtag chk drop ssub ;
: p-sapp ( args -- v ) arg2 strtag chk swap strtag chk swap
  over blen over blen + strtag newbox >r
  over bdat r@ bdat 3 pick blen move
  dup bdat r@ bdat 3 pick blen + 2 pick blen move 2drop r> ;
: scmp ( a b -- n ) over blen over blen min 0 ?do over bdat i + c@ over bdat i + c@ - ?dup if
    nip nip 0< if -1 else 1 then unloop exit then loop
  blen swap blen swap - dup 0< if drop -1 else 0> if 1 else 0 then then ;
: p-scmp ( args -- v ) arg2 strtag chk swap strtag chk swap scmp fix ;
: p-s>sym ( args -- v ) car strtag chk dup blen 63 min >r bdat tok r@ move tok r> intern ;
: p-sym>s ( args -- v ) car dup sym? 0= if s" not a symbol" err then
  name dup strtag newbox dup >r bdat swap move r> ;
: p-newline ( args -- v ) drop cr unspec ;
: p-set-car ( args -- v ) dup cdr car swap car pair car! unspec ;
: p-set-cdr ( args -- v ) dup cdr car swap car pair cdr! unspec ;
: p-forth ( args -- ) drop ssave @ sp! rsave @ rp! ;
: p-exact ( args -- v ) car exact ;
: p-inexact ( args -- v ) car inexact ;
: p-eqv ( args -- v ) dup car swap cdr car eqv bool ;
: p-number? ( args -- v ) car numeric? bool ;
: p-integer? ( args -- v ) car dup fixnum? if drop #t exit then dup flo? if cdr fint? bool exit then drop #f ;
: p-rational? ( args -- v ) car dup flo? if cdr $7F800000 and $7F800000 <> bool exit then dup fixnum? swap rat? or bool ;
: p-exact? ( args -- v ) car dup numeric? 0= if s" not a number" err then dup fixnum? swap rat? or bool ;
: p-inexact? ( args -- v ) car dup numeric? 0= if s" not a number" err then flo? bool ;
: p-exint? ( args -- v ) car fixnum? bool ;
: p-num ( args -- v ) car numden drop >fix ;
: p-den ( args -- v ) car numden nip >fix ;
: p-nan? ( args -- v ) car dup flo? if cdr dup $7F800000 and $7F800000 = swap $7FFFFF and 0<> and bool exit then drop #f ;
: p-ftrunc ( args -- v ) car cdr dup fint? if flo exit then f>s s>f flo ;   \ toward zero
: p-fsqrt ( args -- v ) car >float fsqrt flo ;
: p-inf? ( args -- v ) car dup flo? if cdr $7FFFFFFF and $7F800000 = bool exit then drop #f ;
' p-exact defprim exact   ' p-inexact defprim inexact   ' p-eqv defprim eqv?
' p-number? defprim number?   ' p-number? defprim real?   ' p-number? defprim complex?
' p-integer? defprim integer?   ' p-rational? defprim rational?
' p-exact? defprim exact?   ' p-inexact? defprim inexact?   ' p-exint? defprim exact-integer?
' p-ftrunc defprim %ftruncate   ' p-fsqrt defprim %fsqrt
' p-num defprim %numerator   ' p-den defprim %denominator   ' p-nan? defprim nan?   ' p-inf? defprim infinite?
' p-apply defprim apply   ' p-display defprim display   ' p-write defprim write
' p-string? defprim string?   ' p-vector? defprim vector?   ' p-bv? defprim bytevector?
' p-char? defprim char?   ' p-c>i defprim char->integer   ' p-i>c defprim integer->char
' p-slen defprim string-length   ' p-vlen defprim vector-length   ' p-bvlen defprim bytevector-length
' p-sref defprim string-ref   ' p-sset defprim string-set!   ' p-vref defprim vector-ref
' p-vset defprim vector-set!   ' p-bvref defprim bytevector-u8-ref   ' p-bvset defprim bytevector-u8-set!
' p-mkstr defprim make-string   ' p-mkvec defprim make-vector   ' p-mkbv defprim make-bytevector
' p-s>l defprim %string->list   ' p-v>l defprim %vector->list   ' p-bv>l defprim %bytevector->list
' p-l>s defprim list->string   ' p-l>v defprim list->vector   ' p-l>bv defprim list->bytevector
' p-substr defprim %substring   ' p-sapp defprim %string-append2   ' p-scmp defprim %string-compare
' p-s>sym defprim string->symbol   ' p-sym>s defprim symbol->string
' p-newline defprim newline   ' p-set-car defprim set-car!   ' p-set-cdr defprim set-cdr!
' p-forth defprim forth

: repl begin 0 raw ! ." > " read 0 eval dup unspec = if drop else print then cr again ;
' repl 'repl !
: lisp ( -- ) sp@ ssave ! rp@ rsave ! 1 lpos ! 0 llen ! -1 pk ! cr repl ;
