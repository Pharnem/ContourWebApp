#lang racket/base

(define server-host (getenv "CONTOUR_SERVER_HOST"))
(define server-port (string->number (getenv "CONTOUR_SERVER_PORT")))
(define server-hostname
  (string-append server-host ":" (number->string server-port)))

(define smtp-username (getenv "CONTOUR_SMTP_USERNAME"))
(define smtp-password (getenv "CONTOUR_SMTP_PASSWORD"))
(define smtp-host (getenv "CONTOUR_SMTP_HOST"))
(define smtp-port (string->number (getenv "CONTOUR_SMTP_PORT")))

(define (local->global uri)
  (string-append server-hostname uri))

(provide (all-defined-out))