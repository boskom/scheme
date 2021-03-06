;; Show source code
(js-invoke ($ "#source_view") 'html (js-invoke ($ "#source") 'html))
;(.. ($ "#source_view")
;    `(html ,(http-request "raphaelis.scm")))


;; square - represents a single square
;;   x, y : position in a field
;;   rect : Raphael's rect

(define-record-type square ;=> (make-square x y)
  (fields (mutable x) (mutable y) (immutable rect))
  (protocol
    (lambda (orig-make-square)
      (lambda (x y)
        (let* ((rect (js-invocation *paper*
                         '(rect 0 0 20 20)
                         '(attr ((fill . "pink") (stroke . "#ff8888")))))
               (square (orig-make-square 0 0 rect)))
          (square-move! square x y)
          square)))))

(define square-new! make-square)

(define (square-move! sq x y)
  (square-x-set! sq x)
  (square-y-set! sq y)
  (js-invocation (square-rect sq)
      `(attr ((x . ,(* x 20))
              (y . ,(* y 20))))))

(define (square-die! sq)
  (js-invocation (square-rect sq)
      '(attr ((fill . "#888") (stroke . "#444")))))

;; block - represents a tetromino
;;   shape: list of (xx . yy)
;;   x: 0..10
;;   y: 0..20
;;   squares: list of squares

(define BLOCK-SHAPES '#(
  ((0 . -1)
   (0 . 0)
   (0 . 1)
   (0 . 2)
   (0 . 3))

  ((0 . 0) (1 . 0)
   (0 . 1))

  ((0 . 0) (1 . 0)
   (0 . 1) (1 . 1))
  ))

(define-record-type block ;=> (make-block kind)
  (fields
    (mutable shape) (mutable x) (mutable y) (immutable squares))
  (protocol
    (lambda (orig-make-block)
      (lambda (kind)
        (let* ((shape (vector-ref BLOCK-SHAPES kind))
               (n (length shape))
               (squares (map
                          (lambda (pos) (square-new! 0 0))
                          (iota n))))
           (orig-make-block (list-copy shape) 0 0 squares))))))

(define (block-new!)
  (define (make-kind)
    (random-integer (vector-length BLOCK-SHAPES)))
  (let1 bl (make-block (make-kind))
    (block-move! bl 0 0)
    bl))

(define (block-move! bl x y)
  (block-x-set! bl x)
  (block-y-set! bl y)
  (for-each (lambda (pos sq)
              (square-move! sq (+ x (car pos))
                               (+ y (cdr pos))))
    (block-shape bl)
    (block-squares bl)))

(define (block-die! bl)
  (for-each square-die! (block-squares bl)))

(define (block-place bl x y)
  (map (lambda (pos)
         (cons (+ x (car pos))
               (+ y (cdr pos))))
       (block-shape bl)))

(define (block-rotated-place bl x y)
  (map (lambda (pos)
         (cons (+ x (cdr pos))
               (+ y (- (car pos)))))
       (block-shape bl)))

(define (block-rotate! bl) 
  (block-shape-set! bl (block-rotated-place bl 0 0)))

;; field - represents the 20x10 field
;;   width: 10
;;   height: 20
;;   data: vector(20) of vector(10) of square(or #f)
;;   rect: Raphael's rect

(define-record-type field ;=> (make-field rect)
  (fields (immutable width) (immutable height) 
          (immutable data) (immutable rect))
  (protocol
    (lambda (orig-make-field)
      (lambda (rect)
        (let1 data (vector-map (lambda (_) (make-vector 10 #f))
                               (make-vector 20 'dummy))
          (orig-make-field 10 20 data rect))))))

(define (field-new!)
  (let1 rect (js-invocation *paper* 
                 `(rect 0 0 ,(* 10 20) ,(* 20 20))
                 '(attr ((stroke . "#ccc") (fill . "#ccc"))))
    (make-field rect)))

(define (field-data-ref field x y)
  (if (< y 0)
    #f
    (vector-ref (vector-ref (field-data field) y)
                 x)))

(define (field-data-set! field x y value)
  (vector-set! (vector-ref (field-data field) y)
               x
               value))

(define (field-check field place)
  (define (valid? val lim)
    (and (<= 0 val) (< val lim)))
  (define (usable? pos w h)
    (and (<= 0 (car pos)) (< (car pos) w)
         (< (cdr pos) h)
         (not (field-data-ref field (car pos) (cdr pos)))))

  (let ((w (field-width field))
        (h (field-height field)))
    (for-all (lambda (pos) (usable? pos w h))
             place)))

(define (field-merge-block! field block)
  (let ((x (block-x block))
        (y (block-y block)))
    (for-each (lambda (pos square)
                (field-data-set! field 
                                 (+ x (car pos))
                                 (+ y (cdr pos))
                                 square))
              (block-shape block)
              (block-squares block))))

(define (field-clear-rows! field)
  (define (remove-squares! row)
    (vector-for-each (lambda (sq) 
                       (when sq 
                         (js-invoke (square-rect sq) 'remove)))
                     row))
  (define (filled? row)
    (for-all identity (vector->list row)))
  (define (falldown! rows)
    (let* ((h (field-height field))
           (w (field-width field)))
      (let loop ((tgt (- h 1))
                 (src (- h 1)))
        (unless (< tgt 0)
          (if (< src 0)
            (begin
              (vector-set! rows tgt (make-vector w #f))
              (loop (- tgt 1) src))
            (begin
              (if (filled? (vector-ref rows src))
                (begin
                  (remove-squares! (vector-ref rows src))
                  (loop tgt (- src 1)))
                (begin
                  (vector-set! rows tgt (vector-ref rows src))
                  (vector-for-each
                    (lambda (sq)
                      (when sq
                        (square-move! sq (square-x sq) tgt)))
                    (vector-ref rows src))
                  (loop (- tgt 1) (- src 1))))))))))
  (falldown! (field-data field)))

;;
;; main
;;

(define (Raphael . args)
  (apply js-call `(,(js-eval "Raphael") ,@args)))

(define *paper* (Raphael (js-ref ($ "#field") "0") 200 500))

(let ((field (field-new!))
      (block (block-new!))
      (x 0)
      (y 0))
  (define (main)
    (let loop ()
      (sleep 0.5)
      (inc! y)
      (if (field-check field (block-place block x y))
        (begin
          (block-move! block x y)
          (loop 1))
        (begin
          (block-die! block)
          (field-merge-block! field block)
          (field-clear-rows! field)
          (set! block (block-new!))
          (set! x 0)
          (set! y 0)
          (when (field-check field (block-place block x y))
            (loop 1))))))

  (define (on-keydown e)
    (call/cc (lambda (return)
      (case (js-ref e 'keyCode)
        ((38) ; up(rotate) 
         (when (field-check field (block-rotated-place block x y))
           (block-rotate! block)))
        ((39) ; right 
         (when (field-check field (block-place block (+ x 1) y))
           (inc! x)
           (block-move! block x y)))
        ((37) ; left
         (when (field-check field (block-place block (- x 1) y))
           (dec! x)
           (block-move! block x y)))
        ((40) ; down
         (let loop ()
           (when (field-check field (block-place block x (+ y 1)))
             (inc! y)
             (loop)))
         (block-move! block x y))
        (else
          (return #t)))
      #f)))

  (js-invoke ($ (js-eval "window"))
             'keydown (js-closure on-keydown))

  (main))
