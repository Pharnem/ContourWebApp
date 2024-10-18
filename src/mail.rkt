#lang racket/base
(require net/smtp
         net/head
         racket/match
         racket/string
         racket/contract
         openssl
         "state.rkt"
         "sql.rkt"
         "config.rkt")

(define username "contour.board@gmail.com")
(define password "capm mvpr lkxr hbcv")
(define server "smtp.gmail.com")
(define port 465)

(define/contract (send-mail to subject body)
  (-> string? string? string? void?)
  (smtp-send-message server
                     username
                     (list to)
                     (standard-message-header username (list to) '() '() subject)
                     (string-split (string-replace body "\r" "") "\n")
                     #:port-no port
                     #:auth-user username
                     #:auth-passwd password
                     #:tcp-connect ssl-connect))

(define/contract (request-password-reset email)
  (-> string? (or/c 'user-not-found 'ok))
  (match (sql:get-user-id/email (conn/r) email)
    [#f 'user-not-found]
    [user-id (let ([token (sql:new-request (conn/w) user-id)])
               (send-mail email
                          "Contour - Password Reset"
                          (format "Hi ~a,\nWe are writing because we have received a request to reset the password to your account at Contour.noDomain.com\nIf you wish to reset your password, follow the link below:\n~a\nIf you did not make the request, please ignore this message.\nKind regards,\nCountour team"
                                  email (local->global (format "/requests/~a" token))))
               'ok)]))

(provide send-mail
         request-password-reset)