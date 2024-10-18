#lang racket/base
(require web-server/servlet
         web-server/http/id-cookie
         racket/match
         racket/function
         racket/dict
         racket/string
         json
         xml
         xml/path
         "data.rkt"
         "util.rkt"
         "tags.rkt"
         "pictures.rkt"
         "state.rkt"
         "sql.rkt"
         "auth.rkt")

(define (api:create-picture req)
  (failsafe user #:on-fail (response/jsexpr (hash 'error #t 'status "Couldn't post the picture, are you sure it's in correct format?"))
            (let* ([data (extract-data req '(picture title description tags))]
                   [picture (data 'picture)]
                   [title (data 'title)]
                   [description (data 'description)]
                   [tags  (string-split (data 'tags))]
                   [picture-id (post-picture picture title description tags (user-id (session-user)))]
                   [picture-uri (format "/pictures/~a" picture-id)])
              (response/jsexpr (hash 'id picture-id 'location picture-uri 'status "Picture posted!")))
            ))

(define (api:toggle-delete-picture req picture-id)
  (failsafe user
            (let* ([data (extract-data req '(deleted))]
                   [deleted? (data 'deleted)]
                   [pic (sql:get-picture (conn/r) picture-id)])
              (when (not (or (equal? (picture-author-id pic) (user-id (session-user))) (user-manager? (session-user))))
                (error 'unauthorised))
              (sql:toggle-picture-state (conn/w) picture-id 'deleted deleted? #:issuer-id (user-id (session-user)))
              (response/jsexpr (hash 'deleted deleted?)))))

(define (api:toggle-restrict-picture req picture-id)
  (failsafe manager
            (let* ([data (extract-data req '(restricted))]
                   [restricted? (data 'restricted)])
              (sql:toggle-picture-state (conn/w) picture-id 'restricted restricted? #:issuer-id (user-id (session-user)))
              (response/jsexpr (hash 'restricted restricted?)))))

(define (api:list-authors req)
  (let* ([data (extract-data req '(search banned page page-size))]
         [search-string (data 'search)]
         [banned (equal? (data 'banned) "true")]
         [page (string->number (data 'page "1"))]
         [page-size (string->number (data 'page-size "4"))]
         [page-count (ceiling (/ (sql:count-authors (conn/r) #:like search-string #:banned? banned) page-size))]
         [authors+thumbnails (sql:list-authors (conn/r) #:page page #:per-page page-size #:like search-string #:banned? banned)])
    (response/jsexpr
     (hash
      'page page
      'page-count page-count
      'authors (map
                (λ (a+t)
                  (user->hash/public (car a+t) (hash 'thumbnail (cdr a+t))))
                authors+thumbnails)))))

(define (api:create-user req)
  (failsafe all
            (let* ([data (extract-data req '(email username password repeat-password avatar))]
                   [password (data 'password)])
              (if (equal? password (data 'repeat-password))
                  (let* ([avatar-uri (save-picture "avatars" (data 'avatar))]
                         [new-user-id (sql:new-user (conn/w) (data 'email) (data 'username) (encrypt-password password) avatar-uri)]
                         [user-uri (format "/users/~a" new-user-id)]
                         [new-session-token (sql:new-session (conn/w) new-user-id)])
                    (response/jsexpr (hash 'id new-user-id 'location user-uri 'session-token new-session-token 'status "Registered successfully.")
                                     #:headers (list (cookie->header (make-id-cookie "session"
                                                                                     new-session-token
                                                                                     #:path "/"
                                                                                     #:key (make-secret-salt/file secret-path))))))
                  (response/jsexpr (hash 'error #t 'status "Passwords do not match."))))))

(define (api:change-user-avatar req)
  (failsafe user
            (let* ([data (extract-data req '(avatar))]
                   [avatar (data 'avatar)]
                   [avatar-uri (save-picture "avatars" avatar)])
              (sql:change-user-avatar (conn/w) (user-id (session-user)) avatar-uri)
              (response/jsexpr (hash 'location avatar-uri)))))

(define (api:toggle-ban-user req target-id)
  (failsafe admin
            (let* ([data (extract-data req '(banned))]
                   [banned? (data 'banned)])
              (sql:toggle-ban-user (conn/w) target-id banned? #:issuer-id (user-id (session-user)))
              (response/jsexpr (hash 'banned banned?)))))

(define (api:start-session req)
  (failsafe all
            (let* ([data (extract-data req '(username password))]
                   [username (data 'username)]
                   [password (data 'password)]
                   [user-id (get-verified-user-id username password)]
                   [session (if user-id (sql:new-session (conn/w) user-id) #f)])
              (if session
                  (response/jsexpr (hash 'session-token session 'status "Logged in")
                                   #:headers (list (cookie->header (prepare-session-cookie session))))
                  (response/jsexpr (hash 'error #t 'status "Invalid username or password") #:code 400)))))

(define (api:stop-session req)
  (failsafe user
            (sql:stop-user-sessions (conn/w) (user-id (session-user)))
            (response/jsexpr (hash 'status "Ok"))))

(define (api:change-password req token)
  (failsafe all
            (let* ([data  (extract-data req '(token password repeat-password))]
                   [pass (data 'password)]
                   [rep (data 'repeat-password)])
              (if (equal? pass rep)
                  (match (change-password/request token pass)
                    ['ok (response/jsexpr (hash 'status "Password changed! Please login to continue."))]
                    ['invalid (response/jsexpr (hash 'error #t 'status "Invalid request."))])
                  (response/jsexpr (hash 'error #t 'status "Passwords do not match."))
                  ))))
    
(define (api:bookmark-picture req picture-id)
  (failsafe user
            (let
                ([bookmark  ((extract-data req '(bookmark)) 'bookmark)])
              (sql:toggle-bookmark-picture (conn/w) (user-id (session-user)) picture-id bookmark)
              (response/jsexpr (hash 'bookmark bookmark 'status "Success" 'label (if bookmark "Saved" "Save?"))))))

(define (api:request-password-reset req)
  (failsafe all
            (define data (extract-data req '(email)))
            (match (request-password-reset (data 'email))
              ['user-not-found (response/jsexpr (hash 'error #t 'status "No user for given email address!" #:code 400))]
              ['ok (response/jsexpr (hash 'status "Email sent!"))])))

(provide (all-defined-out))