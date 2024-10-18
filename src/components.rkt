#lang racket/base
(require web-server/http/xexpr
         web-server/templates
         racket/port
         racket/dict
         racket/function
         racket/string
         racket/format
         racket/match
         racket/list
         db
         "data.rkt"
         "tags.rkt"
         "pictures.rkt"
         "sql.rkt"
         "state.rkt"
         )

(define (combine . body)
  (string-join (map ~a body) ""))

(define (maybe condition . value)
  (if condition (string-join (map ~a value) "") ""))

(define (base-form form-title form-uri form-contents
                   #:method [form-method "post"]
                   #:submit-label [form-submit-label "Submit"]
                   #:postnote [form-postnote ""])
  (include-template "../templates/forms/base.html"))
         

(define (login-form)
  (include-template "../templates/forms/login.html"))

(define (register-form)
  (include-template "../templates/forms/register.html"))

(define (recovery-form)
  (include-template "../templates/forms/recovery.html"))

(define (reset-password-form token)
  (include-template "../templates/forms/password-reset.html"))

(define (author-display user-id)
  (let [(usr (sql:get-user (conn/r) user-id))
        (picts (sql:list-pictures (conn/r) #:author user-id #:per-page 4))]
    (include-template "../templates/users/user-profile.html")))

(define (authors-list authors search-string banned)
    (include-template "../templates/users/list.html"))

(define (picture-form)
  (include-template "../templates/forms/post-picture.html"))

(define (pictures-list author tags pictures authors page page-size page-count restricted)
  (include-template "../templates/pictures/list.html"))

(define (picture-display author p)
  (include-template "../templates/pictures/display.html"))

(provide login-form
         register-form
         recovery-form
         reset-password-form
         author-display
         authors-list
         picture-form
         pictures-list
         picture-display
         combine
         maybe)