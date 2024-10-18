#lang racket/base
(require rackunit
         rackunit/text-ui
         racket/function
         racket/file
         racket/match
         racket/promise
         web-server/http
         web-server/test
         web-server/servlet-dispatch
         db
         json
         uuid
         net/url-string
         (except-in net/cookies/server
                    make-cookie)
         "src/sql.rkt"
         "src/data.rkt"
         "src/state.rkt"
         "src/server.rkt"
         "src/auth.rkt")

(define api (make-parameter #f))

(define (start-admin-session)
  (sql:new-session (conn/w) 1)) ;In the prepared testing environment, the prepared admin+manager user has id 1
(define (start-user-session)
  (sql:new-session (conn/w) 2)) ;In the prepared testing environment, the prepared normal user has id 2

(define (session-header session-token)
  (header #"Cookie" (string->bytes/utf-8 (format "session=~a" (cookie-value (prepare-session-cookie session-token))))))

(define (fetch uri
               #:method [method #"post"]
               #:bindings [bindings '()]
               #:headers [headers '()]
               #:body [body #f]
               #:impersonate [impersonating 'none])
  (let ([extra-headers (if body (list (header #"Content-Type" #"application/json")) '())])
    (bytes->jsexpr ((api)
                    (request method (string->url uri)
                             (append (match impersonating
                                       ['none headers]
                                       ['user (cons (session-header (start-user-session)) headers)]
                                       ['admin (cons (session-header (start-admin-session)) headers)]
                                       [(? string? token) (cons (session-header token) headers)])
                                     extra-headers)
                             (delay bindings)
                             body "localhost" 80 "localhost")
                    #:raw? #t))))

(define sample-image-contents (file->bytes "sample.jpg"))
(define db-test-suite
  (test-suite "Contour Tests"
              (test-case "Database/Users"
                         (check-match
                          (sql:get-user (conn/r) (sql:new-user (conn/w) "test1@mail.com" "Test1" "Password" "/path" #f #f))
                          (user _ "test1@mail.com" "Test1" "/path" #f #f #f))
                         (check-exn
                          exn:fail?
                          (thunk
                           (sql:new-user (conn/w) "test1@mail.com" "Test3" "Password" "/path" #f #f))
                          "Disallow duplicate email address")
                         (check-exn
                          exn:fail?
                          (thunk
                           (sql:new-user (conn/w) "test3@mail.com" "Test1" "Password" "/path" #f #f))
                          "Disallow duplicate username")
                         (check-equal?
                          (sql:get-user (conn/r) 3)
                          (user 3 "manager@mail.com" "Manager" "/avatars/manager.jpg" #t #f #f)
                          "Get user by id")
                         (check-equal?
                          (map user-id (sql:list-users (conn/r) #:like "User"))
                          '(2 4 5)
                          "List users with matching usernames")
                         (check-equal?
                          (map user-id (sql:list-users (conn/r) #:banned? #t))
                          '(4)
                          "List banned users")
                         (check-equal?
                          (begin
                            (sql:toggle-ban-user (conn/w) 5 #t #:issuer-id 1)
                            (user-banned? (sql:get-user (conn/r) 5)))
                          #t))
              (test-case "Database/Pictures"
                         (check-match
                          (begin
                            (let* ([id (sql:new-picture (conn/w) 3 "/images/placeholder.jpg" "/images/placeholder-thumb.jpg" "Some picture" "A picture created for tests")]
                                   [pic (sql:get-picture (conn/r) id)])
                              pic))
                          (picture _ "/images/placeholder.jpg" "/images/placeholder-thumb.jpg" 3 "Some picture" "A picture created for tests" '() #f #f _ #f))
                         (check-equal?
                          (begin
                            (sql:assign-tags (conn/w) 5 '("test" "picture#12" "a-ok"))
                            (let ([pic (sql:get-picture (conn/r) 5)])
                              (picture-tags pic)))
                          '("test" "picture#12" "a-ok")
                          )
                         (check-true
                          (begin
                            (sql:toggle-picture-state (conn/w) 4 'deleted #t #:issuer-id 1)
                            (let ([pic (sql:get-picture (conn/r) 4)])
                              (picture-deleted? pic)))
                          "Delete picture")
                         (check-equal?
                          (map picture-id (sql:list-pictures (conn/r) #:author "User"))
                          '(3 2 1)
                          "List pictures created by User")
                         (check-equal?
                          (map picture-id (sql:list-pictures (conn/r) #:tags '("fantasy")))
                          '(2 1)
                          "List pictures tagged 'fantasy'")
                         )
              (test-case "Api/Users"
                         (check-match
                          (bytes->jsexpr ((api)
                                          (request #"post" (string->url "/api/users/")
                                                   '()
                                                   (delay (list
                                                           (binding:form #"email" #"test@test.test")
                                                           (binding:form #"username" #"test")
                                                           (binding:form #"password" #"testpass")
                                                           (binding:form #"repeat-password" #"testpass")
                                                           (binding:file #"avatar" #"filename" '() sample-image-contents)))
                                                   #f "localhost" 80 "localhost")
                                          #:raw? #t))
                          (hash 'id (? exact-integer?)
                                'location (? string?)
                                'session-token (? uuid-string?)
                                'status "Registered successfully."))
                         (check-match
                          (bytes->jsexpr ((api)
                                          (request #"post" (string->url "/api/users/")
                                                   '()
                                                   (delay (list
                                                           (binding:form #"email" #"test1@test.test")
                                                           (binding:form #"username" #"test")
                                                           (binding:form #"password" #"testpass")
                                                           (binding:form #"repeat-password" #"testpass")
                                                           (binding:file #"avatar" #"filename" '() sample-image-contents)))
                                                   #f "localhost" 80 "localhost")
                                          #:raw? #t))
                          (hash 'error #t
                                'status (? string?)))
                         (check-match
                          (bytes->jsexpr ((api)
                                          (request #"post" (string->url "/api/sessions/")
                                                   '()
                                                   (delay (list
                                                           (binding:form #"username" #"test")
                                                           (binding:form #"password" #"testpass")))
                                                   #f "localhost" 80 "localhost")
                                          #:raw? #t))
                          (hash 'session-token (? uuid-string?) 'status (? string?)))
                         (check-match
                          (bytes->jsexpr ((api)
                                          (request #"post" (string->url "/api/sessions/")
                                                   '()
                                                   (delay (list
                                                           (binding:form #"username" #"test")
                                                           (binding:form #"password" #"testpass")))
                                                   #f "localhost" 80 "localhost")
                                          #:raw? #t))
                          (hash 'session-token (? uuid-string?) 'status (? string?)))
                         (check-match
                          (let* ([token (hash-ref (fetch "/api/sessions/"
                                                         #:bindings (list
                                                                     (binding:form #"username" #"test")
                                                                     (binding:form #"password" #"testpass")))
                                                  'session-token)])
                            (fetch "/api/sessions/current"
                                   #:method #"delete"
                                   #:impersonate token))
                          (hash 'status "Ok"))
                         (let ([test-user (sql:get-user-id/email (conn/r) "test@test.test")])
                           (check-match
                            (fetch (format "/api/users/~a/banned" test-user)
                                   #:bindings (list
                                               (binding:form #"banned" #"true"))
                                   #:impersonate 'user)
                            (hash 'error #t 'status (? string?)))
                           (check-match
                            (fetch (format "/api/users/~a/banned" test-user)
                                   #:body (jsexpr->bytes (hash 'banned #t))
                                   #:impersonate 'admin)
                            (hash 'banned #t))
                           )
                         (check-match
                          (fetch "/api/authors/?page=1"
                                 #:method #"get")
                          (hash 'page 1 'page-count (? exact-integer?)
                                'authors (list (hash 'id (? exact-integer?) 'name (? string?) 'avatar (? string?) 'extra (hash 'thumbnail (? string?))) ...))
                          ))
              (test-case "Api/Pictures"
                         (check-match
                            (fetch "/api/pictures/"
                                   #:method #"post"
                                   #:impersonate 'admin
                                   #:bindings (list (binding:form #"title" #"TEST-TITLE")
                                                    (binding:form #"description" #"TEST-DESCRIPTION")
                                                    (binding:form #"tags" #"ala ma kota")
                                                    (binding:file #"picture" #"filename" '() sample-image-contents)))
                            (hash 'id (? exact-integer?) 'location (? string?) 'status (? string?)))
                         (let
                             ([posted-picture-id (query-value (conn/r) "SELECT max(id) FROM Picture;")])
                           (check-match
                            (fetch (format "/api/pictures/~a/deleted" posted-picture-id)
                                   #:impersonate 'user
                                   #:body (jsexpr->bytes (hash 'deleted #t)))
                            (hash 'error #t 'status (? string?)))
                           (check-match
                            (fetch (format "/api/pictures/~a/deleted" posted-picture-id)
                                   #:impersonate 'admin
                                   #:body (jsexpr->bytes (hash 'deleted #t)))
                            (hash 'deleted #t))
                           ))))

(define (test #:keep [keep-test-db? #f])
  (define filename "contour-current-test.db")
  (when (file-exists? filename)
    (delete-file filename))
  (copy-file "contour-test.db" "contour-current-test.db")
  (define dbr (sqlite3-connect
               #:database "contour-current-test.db"
               #:mode 'read-only))
  (define dbw (sqlite3-connect
               #:database "contour-current-test.db"
               #:mode 'read/write))
  (parameterize ([conn/r dbr]
                 [conn/w dbw]
                 [api (make-dispatcher-tester (make-dispatcher #:conn/r dbr #:conn/w dbw #:log #f))])
    (run-tests db-test-suite))
  (disconnect dbr)
  (disconnect dbw)
  (when (not keep-test-db?)
    (delete-file filename)))

(define tester (test #:keep #f))