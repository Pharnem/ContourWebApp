#lang racket/base
(require db
         racket/string
         "src/sql.rkt"
         "src/util.rkt")

(define dbr (sqlite3-connect
             #:database "contour.db"
             #:mode 'read-only))

(define (list-db-contents)
  (map (compose simplify-path path->complete-path string->path content-uri->path)
       (append
        (query-list dbr "SELECT fullsize FROM Picture")
        (query-list dbr "SELECT thumbnail FROM Picture")
        (query-list dbr "SELECT avatar FROM User"))))

(define (list-files)
  (map (compose simplify-path path->complete-path)
       (append
        (directory-list "content/avatars" #:build? #t)
        (directory-list "content/images" #:build? #t)
        (directory-list "content/thumbnails" #:build? #t))))

(define (clean-contents)
  (let* ([to-be-kept (list-db-contents)]
         [existing (list-files)]
         [to-be-removed (filter (λ (filepath) (not (ormap (λ (contentpath) (equal? filepath contentpath)) to-be-kept))) existing)])
    (for ([f to-be-removed])
      (delete-file f))
    to-be-removed))

; Change local environment, note that it doesn't affect the system-wide environment.
(define (setup-env
         #:host [host "localhost"]
         #:port [port 80]
         #:smtp-host [smtp-host "smtp.gmail.com"]
         #:smtp-port [smtp-port 465]
         #:smtp-username [smtp-username "contour.board@gmail.com"]
         #:smtp-password smtp-password
         )
  (define env-data
    (hash
     "CONTOUR_SERVER_HOST" host
     "CONTOUR_SERVER_PORT" (number->string port)
     "CONTOUR_SMTP_HOST" smtp-host
     "CONTOUR_SMTP_PORT" (number->string smtp-port)
     "CONTOUR_SMTP_USERNAME" smtp-username
     "CONTOUR_SMTP_PASSWORD" smtp-password))
  (hash-for-each env-data
                 putenv))