#lang racket/base
(require db
         web-server/servlet
         web-server/servlet-env
         web-server/http/id-cookie
         racket/match
         racket/contract
         uuid
         crypto
         crypto/libcrypto
         "data.rkt"
         "sql.rkt"
         "util.rkt"
         "state.rkt"
         "mail.rkt"
         "config.rkt")

;Setup OpenSSL crypto factory
(crypto-factories libcrypto-factory)
(define kdf-impl (get-kdf 'scrypt))
(define/contract (encrypt-password pass)
  (-> string? string?)
  (pwhash kdf-impl (string->bytes/utf-8 pass) '((ln 14))))
(define/contract (check-password pass hashed)
  (-> string? string? boolean?)
  (pwhash-verify kdf-impl (string->bytes/utf-8 pass) hashed))

; We use secret-path for sessions - they are supposed to be short-lived, hence we do not preconfigure the secret
(define secret-path (build-path (current-directory) "secret")) 

(define (prepare-session-cookie token)
  (make-id-cookie "session"
                  token
                  #:path "/"
                  #:key (make-secret-salt/file secret-path)))

(define (request->session-token req)
  (request-id-cookie req #:name "session" #:key (make-secret-salt/file secret-path)))

(define/contract (check-user-password user password)
  (-> string? string? boolean?)
  (define hashed (sql:get-user-password-hash (conn/r) user))
  (check-password password hashed))

(define/contract (get-verified-user-id user password)
  (-> string? string? (or/c exact-integer? #f))
  (if (check-user-password user password)
      (sql:get-user-id/username (conn/r) user)
      #f))

(define/contract (change-password/request token new-password)
  (-> string? string? (or/c'ok 'invalid))
  (define hashed (encrypt-password new-password))
  (if (sql:change-user-password (conn/w) token hashed) 'ok 'invalid))

(provide encrypt-password
         check-password
         secret-path
         prepare-session-cookie
         request->session-token
         request-password-reset
         change-password/request
         get-verified-user-id)