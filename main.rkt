#lang racket/base
(require db
         "src/server.rkt")


(define dbr (sqlite3-connect
             #:database "contour.db"
             #:mode 'read-only))

(define dbw (sqlite3-connect
             #:database "contour.db"
             #:mode 'read/write))

(define stop-server (start-server (make-dispatcher
               #:conn/r dbr
               #:conn/w dbw)))
