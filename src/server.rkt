#lang racket/base
(require db
         web-server/dispatchers/dispatch
         racket/contract
         racket/string
         racket/match
         web-server/servlet
         web-server/servlet-env
         (only-in web-server/dispatchers/dispatch-sequencer
                    (make dispatch-in-sequence))
         (only-in web-server/dispatchers/dispatch-files
                    (make dispatch/files))
         (only-in web-server/dispatchers/dispatch-logresp
                  (make dispatch-with-log))
         (only-in web-server/dispatchers/dispatch-lift
                  (make dispatch/lift))
         (only-in web-server/private/mime-types
                  make-path->mime-type)
         web-server/web-server
         web-server/servlet-dispatch
         web-server/dispatchers/filesystem-map
         "pages.rkt"
         "api.rkt"
         "auth.rkt"
         "sql.rkt"
         "state.rkt"
         "config.rkt")

(define (root req) (redirect-to "/pictures/"))
(define (add/ req) (redirect-to (string-append (url->string (request-uri req)) "/") temporarily/same-method))
(define (remove/ req) (redirect-to (string-append (request-uri req) "/") temporarily/same-method))

(define (read-accept accept)
  (define ls (map string-trim (string-split accept ",")))
  (if (ormap (λ (s) (string-prefix? s "application/json")) ls)
      'json
      (if (ormap (λ (s) (string-prefix? s "application/xml")) ls)
          'xml
          'html)))

(define-values (url->servlet servlet->url)
  (dispatch-rules
   [("") root]
   [("api" "sessions" "") #:method "post" api:start-session]
   [("api" "sessions" "current") #:method "delete" api:stop-session]
   [("api" "pictures") #:method "post" add/]
   [("api" "pictures" "") #:method "post" api:create-picture]
   [("api" "pictures" (integer-arg) "deleted") #:method "post" api:toggle-delete-picture]
   [("api" "pictures" (integer-arg) "restricted") #:method "post" api:toggle-restrict-picture]
   [("api" "pictures" (integer-arg) "bookmark") #:method "post" api:bookmark-picture]
   [("api" "users" "") #:method "post" api:create-user]
   [("api" "users" "me" "avatar") #:method "post" api:change-user-avatar]
   [("api" "users" (integer-arg) "banned") #:method "post" api:toggle-ban-user]
   [("api" "authors" "") api:list-authors] ; NOTE: API-wise, we differentiate users (all users) and authors (users who have posted something)
   [("requests" "") #:method "post" api:request-password-reset]
   [("requests" (string-arg)) page:change-password]
   [("requests" (string-arg)) #:method "post" api:change-password]
   [("users" "me") page:display-myself]
   [("users" "me" "bookmarks") page:list-bookmarks]
   [("users" (integer-arg)) page:display-author]
   [("users" "") page:list-authors]
   [("users") add/]
   [("login") page:login]
   [("register") page:register]
   [("recovery") page:recovery]
   [("pictures") add/]
   [("pictures" "") page:list-pictures]
   [("pictures" (integer-arg)) page:show-picture]
   [("pictures" "new") page:new-picture]
   [("ping") (λ (req) (printf "Ping:\n~a\n" req) (response/empty))]
   ;[("error") page:error]
   ))
(define mime-types-path "./conf/mime.types")

(define (error-dispatcher)
  (dispatch/lift page:error))
(define (static-dispatcher)
  (dispatch/files #:url->path (make-url->path "./static")
                  #:path->mime-type (make-path->mime-type mime-types-path)))
(define (content-dispatcher)
  (dispatch/files #:url->path (make-url->path "./content")
                  #:path->mime-type (make-path->mime-type mime-types-path)))

(define (page+api-dispatcher #:conn/r dbr #:conn/w dbw)
  (dispatch/servlet (λ (req)
                    (parameterize* ([headers (request-headers/raw req)]
                                    [bindings (request-bindings/raw req)]
                                    [conn/r dbr]
                                    [conn/w dbw]
                                    [session-user (sql:get-user (conn/r) (sql:get-user-id/session (conn/r) (request->session-token req)))])
                      (url->servlet req)))))

(define/contract (make-dispatcher #:conn/r dbr #:conn/w dbw #:log [log? #t] #:log-path [log-path (current-output-port)])
  (->* [#:conn/r connection? #:conn/w connection?] [#:log boolean? #:log-path (or/c path-string? output-port?)] dispatcher/c) 
  (let ([base (dispatch-in-sequence (page+api-dispatcher #:conn/r dbr #:conn/w dbw)
                                    (static-dispatcher)
                                    (content-dispatcher)
                                    (error-dispatcher))])
    (if log?
        (dispatch-with-log base
                           #:format 'extended
                           #:log-path log-path)
        base)))

(define (start-server dispatcher #:listen-ip [listen-ip server-host] #:port [port server-port])
  (serve #:dispatch dispatcher
         #:listen-ip listen-ip
         #:port port))

(provide
 make-dispatcher
 start-server)