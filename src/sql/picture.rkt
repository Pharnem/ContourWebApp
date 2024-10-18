#lang racket/base
(require racket/contract
         db
         uuid
         racket/list
         racket/match
         racket/string
         racket/function
         gregor
         "common.rkt"
         "../data.rkt")

(define/contract (new-picture conn user-id fullsize-uri thumbnail-uri title description)
  (-> connection? rowid? string? string? string? string? rowid?)
  (query-value conn "INSERT INTO Picture (user_id, fullsize, thumbnail, title, description) VALUES (?,?,?,?,?) RETURNING rowid" user-id fullsize-uri thumbnail-uri title description))

(define/contract (toggle-picture-state conn picture-id aspect value #:issuer-id issuer-id)
  (-> connection? rowid? (or/c 'deleted 'restricted) boolean? #:issuer-id (or/c rowid? #f) void?)
  (query-exec conn
              (format
               "WITH issuer(id,superuser) AS (SELECT id, (manager=1 OR admin=1) AS superuser FROM User WHERE id=?)
UPDATE Picture SET ~a=? WHERE id=? AND (user_id=(SELECT id FROM issuer) OR 1=(SELECT superuser FROM issuer))"
               (if (equal? aspect 'deleted) "deleted" "restricted")) (or issuer-id sql-null) (if value 1 0) picture-id))

(define/contract (toggle-bookmark-picture conn user-id picture-id bookmarked?)
  (-> connection? rowid? rowid? boolean? void?)
  (match bookmarked?
    [#t (query-exec conn "INSERT OR IGNORE INTO Bookmark (user_id,picture_id) VALUES (?,?)" user-id picture-id)]
    [#f (query-exec conn "DELETE FROM Bookmark WHERE user_id=? AND picture_id=?" user-id picture-id)]))

(define/contract (count-pictures conn #:author [author #f] #:tags [filter-tags '()] #:restricted? [restricted? #f] #:page [page 1] #:per-page [page-size 10]  #:user-id [user-id #f] #:bookmarked [bookmarked #f])
  (->* [connection?] [#:author (or/c string? #f) #:tags (listof string?) #:restricted? boolean? #:page exact-integer? #:per-page exact-integer?  #:user-id (or/c rowid? #f) #:bookmarked boolean?] exact-integer?)  
  (let* ([tag-count (length filter-tags)]
         [tag-list-template (format "(~a)" (string-join (make-list tag-count "?") ","))]
         [restricted-condition (if restricted? "(P.restricted=1) AND" "(P.restricted=0) AND")]
         [author-condition (if author "(? IS NULL OR P.user_id = ?) AND" "")]
         [bookmark-condition (if bookmarked "AND EXISTS (SELECT 1 FROM Bookmark WHERE picture_id=P.id AND user_id=?)" "")]
         [query-string (format "
WITH tag_list(tag) AS (SELECT id FROM Tag WHERE label IN ~a)
SELECT COUNT(*) FROM Picture AS P
INNER JOIN User AS U ON P.user_id=U.id AND U.banned=0
WHERE
~a
~a
deleted=0 AND
EXISTS (
    SELECT 1 
    FROM Tagging AS Tg
    INNER JOIN Tag AS T ON T.id=Tg.tag_id
    WHERE (T.id IN (SELECT * FROM tag_list) OR ?=0) ~a
    AND Tg.picture_id=P.id
    GROUP BY Tg.picture_id
    HAVING (?=0 OR COUNT(DISTINCT T.label) = ?)
);" tag-list-template restricted-condition author-condition bookmark-condition)])
    (apply query-value
           conn
           query-string
           (append filter-tags
                   (if author (make-list 2 author) '())
                   (if bookmarked (list user-id) '())
                   (make-list 3 tag-count)))))


(define/contract
  (list-pictures conn
                 #:author [author #f]
                 #:tags [filter-tags '()]
                 #:restricted? [restricted? #f]
                 #:page [page 1] #:per-page [page-size 10]
                 #:user-id [user-id #f]
                 #:bookmarked [bookmarked #f])
  (->* [connection?]
       [#:author (or/c rowid? string? #f)
        #:tags (listof string?)
        #:restricted? boolean?
        #:page exact-integer? #:per-page exact-integer?
        #:user-id (or/c rowid? #f)
        #:bookmarked boolean?]
       (listof picture?))
  (define query-string (format "
WITH tag_list(tag) AS (SELECT id FROM Tag WHERE label IN (~a))
SELECT P.id, P.fullsize, P.thumbnail, P.user_id, P.title,
       P.description, group_concat(Tag.label,' ') AS tags, P.deleted, P.restricted, P.created_at,
EXISTS (SELECT 1 FROM Bookmark WHERE picture_id=P.id AND user_id=?) AS bookmark
FROM Picture AS P
INNER JOIN User AS U ON P.user_id=U.id AND U.banned=0
LEFT JOIN Tagging ON P.id=Tagging.picture_id
LEFT JOIN Tag ON tag_id=Tag.id
WHERE deleted=0 AND restricted=? AND (? IS NULL OR U.~a = ?) AND bookmark>=?
GROUP BY P.id, P.fullsize, P.thumbnail, P.user_id, P.title,
         P.description, P.deleted, P.restricted, P.created_at, EXISTS (SELECT 1 FROM Bookmark WHERE picture_id=P.id AND user_id=?)
HAVING SUM(IIF(Tag.id IN (SELECT tag FROM tag_list),1,0))=~a
ORDER BY P.id DESC
LIMIT ? OFFSET ?"
                               (string-join (map (thunk* "?") filter-tags) ",") (if (rowid? author) "id" "username") (length filter-tags)))
  (for/list ([(id fullsize thumbnail author-id title description tags deleted? restricted? created-at maybe-bookmark)
              (apply in-query
                     conn
                     query-string
                     (append filter-tags
                             (list (or user-id sql-null) (if restricted? 1 0) (or author sql-null) (or author sql-null) (if bookmarked 1 0) (or user-id sql-null) page-size (* page-size (- page 1)))))])
    (picture id fullsize thumbnail author-id
             title description (string-split (if (sql-null? tags) "" tags))
             (= 1 deleted?) (= 1 restricted?)
             (posix->datetime (string->number created-at))
             (if user-id
                 (if (= 1 maybe-bookmark) #t #f)
                 #f))))
              
(define/contract (get-picture conn picture-id #:user-id [user-id #f])
  (->* [connection? rowid?] [#:user-id (or/c rowid? #f)] (or/c picture? #f))
  (define maybe-picture
    (for/list ([(id fullsize thumbnail author-id title description tags deleted? restricted? created-at maybe-bookmark)
                (in-query conn "
SELECT P.id, P.fullsize, P.thumbnail, P.user_id, P.title,
P.description, group_concat(Tag.label,' ') AS tags, P.deleted, P.restricted, P.created_at,
EXISTS (SELECT 1 FROM Bookmark WHERE picture_id=P.id AND user_id=?) AS bookmark
FROM Picture AS P
LEFT JOIN Tagging ON P.id=Tagging.picture_id
LEFT JOIN Tag ON tag_id=Tag.id
WHERE P.id=?
GROUP BY P.id, P.fullsize, P.thumbnail, P.user_id, P.title,
P.description, P.deleted, P.restricted, P.created_at, EXISTS (SELECT 1 FROM Bookmark WHERE picture_id=P.id AND user_id=?);" (or user-id sql-null) picture-id (or user-id sql-null))])
      (picture id fullsize thumbnail author-id
               title description
               (string-split (if (sql-null? tags) "" tags))
               (= 1 deleted?) (= 1 restricted?)
               (posix->datetime (string->number created-at))
               (if user-id
                   (if (= 1 maybe-bookmark) #t #f)
                   #f))))
  (if (= (length maybe-picture) 1)
      (car maybe-picture)
      #f))

(define/contract (assign-tags conn picture-id tags)
  (-> connection? rowid? (listof string?) void?)
  (apply query-exec conn
         (format "INSERT OR IGNORE INTO Tag (label) VALUES ~a;"
                 (string-join (map (thunk* "(?)") tags) ","))
         tags)  
  (apply query-exec conn
         (format "
WITH tags_list(id) AS (SELECT id FROM Tag WHERE label IN (~a))
INSERT INTO Tagging (picture_id, tag_id)
SELECT ? AS picture_id, id AS tag_id FROM tags_list;"
                 (string-join (map (thunk* "?") tags) ","))
         (append tags (list picture-id))))

(define/contract (list-bookmark-ids conn user-id)
  (-> connection? (or/c rowid? #f) (listof rowid?))
  (query-list conn "SELECT picture_id FROM Bookmark WHERE user_id=?" (or user-id sql-null)))

(provide (all-defined-out))