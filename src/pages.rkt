#lang racket/base
(require web-server/servlet
         web-server/http/xexpr
         web-server/templates
         db
         racket/match
         racket/string
         "util.rkt"
         "data.rkt"
         "components.rkt"
         "pictures.rkt"
         "state.rkt"
         "sql.rkt")

(define (render-page title content
                     #:discriminator [discriminator #f]
                     #:styles [styles '()]
                     #:scripts [scripts '()]
                     . content-args)
  (response/xexpr
   (include-template/xml "../templates/layout.html")))

(define (render-form title content
                     #:discriminator [discriminator #f]
                     . content-args)
  (let ([styles '("forms")]
        [scripts '("forms")])
    (response/xexpr
     (include-template/xml "../templates/layout.html"))))

(define (page:display-myself req)
  (failsafe user #:on-fail (redirect-to "/login")
      (render-page "Profile" author-display (user-id (session-user))
                   #:discriminator 'user
                   #:styles '("profile" "forms")
                   #:scripts '("forms" "buttons"))
      ))

(define (page:display-author req user-id)
  (render-page "Profile" author-display user-id
               #:styles '("profile" "forms")
               #:scripts '("forms" "buttons")))

(define (page:list-authors req)
    (let* ([data (extract-data req '(search-string banned))]
           [search-string (data 'search-string)]
           [banned (equal? (data 'banned) "true")]
           [authors (sql:list-authors (conn/r) #:like search-string #:banned? banned)])
      (render-page "Authors" authors-list authors search-string banned
                   #:discriminator 'authors
                   #:styles '("authors" "forms")
                   #:scripts '("authors"))))

(define (page:login req) (render-form "Login" login-form
                                      #:discriminator 'user))
(define (page:register req) (render-form "Register" register-form))
(define (page:recovery req)
  (render-form "Recover password" recovery-form))

(define (page:change-password req token)
  (render-form "Reset password" reset-password-form token))

(define (page:error req) (response/jsexpr "404 Not found." #:code 404))

(define (page:new-picture req)
  (render-form "Post new picture" picture-form
               #:discriminator 'post))

(define (page:show-picture req picture-id)
  (let* ([pic (sql:get-picture (conn/r) picture-id #:user-id (if (session-user) (user-id (session-user)) #f))]
         [author (sql:get-user (conn/r) (picture-author-id pic))])
    (if (or (not (picture-restricted? pic)) (and (session-user) (user-manager? (session-user))))
        (render-page (picture-title pic) picture-display author pic
                     #:styles '("focus")
                     #:scripts '("buttons"))
        (redirect-to "/pictures/"))))

(define (page:list-pictures req)
  (let* ([data (extract-data req '(author tags page page-size restricted))]
         [author (data 'author)]
         [tags ((compose string-split string-downcase) (data 'tags ""))]
         [page (string->number (data 'page "1"))]
         [page-size (string->number (data 'page-size "4"))]
         [restricted (if (and (equal? (data 'restricted) "true") (session-user) (user-manager? (session-user))) #t #f)]
         [picture-count (sql:count-pictures (conn/r) #:author (if (not (equal? author "")) author #f) #:tags tags #:page page #:per-page page-size #:restricted? restricted #:user-id (if (session-user) (user-id (session-user)) #f))]
         [page-count (ceiling (/ picture-count page-size))]
         [pictures (sql:list-pictures (conn/r) #:author (if (not (equal? author "")) author #f) #:tags tags #:page page #:per-page page-size #:restricted? restricted #:user-id (if (session-user) (user-id (session-user)) #f))]
         [authors (make-hash (map (λ (u) (cons (user-id (car u)) (car u))) (sql:list-authors (conn/r))))])
    (render-page "Pictures" pictures-list author tags pictures authors page page-size page-count (data 'restricted)
                 #:discriminator 'pictures
                 #:styles '("cards")
                 #:scripts '("buttons"))))

(define (page:list-bookmarks req)
  (failsafe user #:on-fail (redirect-to "/login" see-other)
            (let* ([data (extract-data req '(author tags page page-size))]
                   [author (data 'author)]
                   [tags ((compose string-split string-downcase) (data 'tags ""))]
                   [page (string->number (data 'page "1"))]
                   [page-size (string->number (data 'page-size "4"))]
                   [picture-count (sql:count-pictures (conn/r) #:author (if (not (equal? author "")) author #f) #:tags tags #:page page #:per-page page-size #:restricted? #f #:user-id (user-id (session-user))  #:bookmarked #t)]
                   [page-count (ceiling (/ picture-count page-size))]
                   [pictures (sql:list-pictures (conn/r) #:author (if (not (equal? author "")) author #f) #:tags tags #:page page #:per-page page-size #:restricted? #f #:user-id (user-id (session-user)) #:bookmarked #t)]
                   [authors (make-hash (map (λ (u) (cons (user-id (car u)) (car u))) (sql:list-authors (conn/r))))])
              (render-page "Pictures" pictures-list author tags pictures authors page page-size page-count #f
                           #:discriminator 'bookmarks
                           #:styles '("cards")
                           #:scripts '("buttons")))))

(provide (all-defined-out))