#lang racket/base
(require racket/contract
         racket/match
         web-server/servlet)

; REQUEST
(define session-user (make-parameter #f))
(define bindings (make-parameter '()))
(define headers (make-parameter '()))
(define body (make-parameter '()))

; DATABASE
(define conn/r (make-parameter #f))
(define conn/w (make-parameter #f))

(define/contract (content-type)
  (-> (or/c 'json 'xml 'default))
  (match (headers-assq* #"Content-Type" (headers))
    ((struct* header ([value #"application/json"])) 'json)
    ((struct* header ([value #"application/xml"])) 'xml)
    (_ 'default)))
    
  
(provide (all-defined-out))