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

(define/contract (new-user conn email username password avatar-uri [manager? #f] [admin? #f])
  (->* [connection? string? string? string? string?] [boolean? boolean?] rowid?)
  (query-value conn "INSERT INTO User (email, username, password, avatar, manager, admin) VALUES (?,?,?,?,?,?) RETURNING rowid" email username password avatar-uri (if manager? 1 0) (if admin? 1 0)))

(define/contract (toggle-ban-user conn user-id banned? #:issuer-id issuer-id)
  (-> connection? rowid? boolean? #:issuer-id rowid? void?)
  (query-exec conn "WITH issuer(id,admin) AS (SELECT id,admin FROM User WHERE id=?) 
UPDATE User SET banned=? WHERE id=? AND 1=(SELECT admin FROM issuer) AND NOT id=(SELECT id FROM issuer)" issuer-id (if banned? 1 0) user-id))

(define/contract (get-user conn user-id)
  (-> connection? (or/c rowid? #f) (or/c user? #f))
  (define maybe-user (for/list ([(id username avatar manager admin email banned)
                                 (in-query conn "SELECT id,username,avatar,manager,admin,email,banned FROM User WHERE id=?" (or user-id sql-null))])
                       (user id email username avatar (= manager 1) (= admin 1) (= banned 1))))
  (if (= (length maybe-user) 1)
      (car maybe-user)
      #f))

(define/contract (list-users conn #:like [search-string ""] #:banned? [banned? '()])
  (->* [connection?] [#:like string? #:banned? (or/c boolean? '())] (listof user?))
  (define filter-banned (match banned? [#t 1] [#f 0] ['() sql-null]))
  (for/list ([(id username avatar manager admin email banned)
              (in-query conn "SELECT id,username,avatar,manager,admin,email,banned FROM User WHERE username LIKE ? AND (? IS NULL OR banned=?) ORDER BY id" (string-append "%" search-string "%") filter-banned filter-banned)])
    (user id email username avatar (= manager 1) (= admin 1) (= banned 1))))

(define/contract (count-authors conn #:like [search-string #f] #:banned? [banned? #f])
  (->* [connection?] [#:like (or/c string? #f) #:banned? boolean?] exact-integer?)
  (define query-string
    "WITH P AS (
  SELECT Picture.*, ROW_NUMBER() OVER (PARTITION BY Picture.user_id ORDER BY id DESC) AS rank
  FROM Picture
)
SELECT COUNT(*) 
FROM User AS U 
INNER JOIN P ON U.id=P.user_id
WHERE P.rank=1
AND U.username LIKE '%' || ? || '%'
AND U.banned=?")
  (query-value conn query-string (or search-string "") (if banned? 1 0)))

(define/contract (list-authors conn #:like [search-string #f] #:banned? [banned? #f] #:page [page 1] #:per-page [page-size 10])
  (->* [connection?] [#:like (or/c string? #f) #:banned? boolean? #:page exact-integer? #:per-page exact-integer?] (listof (cons/c user? string?)))
  (define query-string
    "WITH P AS (
  SELECT Picture.*, ROW_NUMBER() OVER (PARTITION BY Picture.user_id ORDER BY id DESC) AS rank
  FROM Picture WHERE deleted=0
)
SELECT U.id AS user_id,U.username,U.avatar,U.manager,U.admin,U.email,U.banned,
       P.thumbnail 
FROM User AS U 
INNER JOIN P ON U.id=P.user_id
WHERE P.rank=1
AND U.username LIKE '%' || ? || '%'
AND U.banned=?
ORDER BY U.username
LIMIT ? OFFSET ?")
  (for/list ([(user-id username avatar manager admin email banned thumbnail)
              (in-query conn query-string (or search-string "") (if banned? 1 0) page-size (* page-size (sub1 page)))])
    (cons (user user-id email username avatar (= manager 1) (= admin 1) (= banned 1)) thumbnail)))

(provide (all-defined-out))