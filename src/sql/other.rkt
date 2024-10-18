#lang racket/base
(require racket/contract
         db
         uuid
         racket/match
         racket/string
         racket/function
         gregor
         "common.rkt"
         "../data.rkt")

(define/contract (new-request conn user-id)
  (-> connection? rowid? uuid-string?)
  (let ([token (uuid-string)])
    (query-exec conn "INSERT INTO Request (user_id, token) VALUES (?,?)" user-id token)
    token))

(define/contract (revoke-request conn token)
  (-> connection? uuid-string? void?)
  (query-exec conn "UPDATE Request SET revoked=1 WHERE token=?" token))

(define/contract (change-user-password conn request-token new-password)
  (-> connection? uuid-string? string? boolean?)
  (start-transaction conn)
  (if (query-value conn "SELECT 1 FROM Request WHERE token=? AND revoked=0 AND Request.expires_at>strftime('%s','now')" request-token)
      (begin
        (query-exec conn "UPDATE User SET password=? WHERE id=(SELECT user_id FROM Request WHERE token=? AND revoked=0 AND Request.expires_at>strftime('%s','now'))" new-password request-token)
        (query-exec conn "UPDATE Request SET revoked=1 WHERE id=(SELECT user_id FROM Request WHERE token=? AND revoked=0 AND Request.expires_at>strftime('%s','now'))" request-token)
        (commit-transaction conn)
        #t)
      (begin
        (rollback-transaction conn)
        #f)))

(define/contract (change-user-avatar conn user-id new-avatar)
  (-> connection? rowid? string? void?)
  (query-exec conn "UPDATE User SET avatar=? WHERE id=?" new-avatar user-id))

(define/contract (get-user-id/request conn token)
  (-> connection? uuid-string? (or/c rowid? #f))
  (query-maybe-value conn "SELECT user_id FROM Request WHERE token=?" token))

(define/contract (get-user-id/email conn email)
  (-> connection? string? (or/c rowid? #f))
  (query-maybe-value conn "SELECT id FROM User WHERE email=?" email))

(define/contract (get-user-id/username conn name)
  (-> connection? string? (or/c rowid? #f))
  (query-maybe-value conn "SELECT id FROM User WHERE username=?" name))

(define/contract (get-user-id/session conn session-token)
  (-> connection? (or/c uuid-string? #f) (or/c rowid? #f))
  (query-maybe-value conn "SELECT user_id FROM Session WHERE token=? AND strftime('%s','now')<expires_at AND revoked=0" (or session-token sql-null)))

(define/contract (get-user-password-hash conn user)
  (-> connection? string? (or/c string? #f))
  (query-maybe-value conn "SELECT password FROM User WHERE username=?" user))

(define/contract (new-session conn user-id)
  (-> connection? rowid? uuid-string?)
  (let ([token (uuid-string)])
    (query-value conn "INSERT INTO Session (user_id, token) VALUES (?,?) RETURNING rowid" user-id token)
    token))

(define/contract (stop-user-sessions conn user-id)
  (-> connection? exact-integer? void?)
  (query-exec conn "UPDATE Session SET revoked=1 WHERE expires_at>strftime('%s','now') AND user_id=?" user-id))

(provide (all-defined-out))