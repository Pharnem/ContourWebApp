#lang racket/base
(require racket/contract
         gregor)

(struct user
  (id email name avatar manager? admin? banned?)
  #:transparent)

(define/contract (user->hash/public u [extra (hash)])
  (->* [user?] [hash?] hash?)
  (hash 'id (user-id u)
        'name (user-name u)
        'avatar (user-avatar u)
        'extra extra))
        

(struct picture
  (id fullsize thumbnail author-id title description tags deleted? restricted? created-at bookmark)
  #:transparent)

(define/contract (picture->hash/public p [extra (hash)])
  (->* [picture?] [hash?] hash?)
  (hash 'id (picture-id p)
        'author (picture-author-id p)
        'fullsize (picture-fullsize p)
        'thumbnail (picture-thumbnail p)
        'title (picture-title p)
        'decription (picture-description p)
        'tags (picture-tags p)
        'bookmarked (if (null? (picture-bookmark p)) 'null (picture-bookmark p))
        'created (picture-created-at p)))

(provide
 (contract-out
          [struct user ((id exact-integer?)
                        (email string?) (name string?)
                        (avatar path-string?)
                        (manager? boolean?) (admin? boolean?)
                        (banned? boolean?))]
          [struct picture ((id exact-integer?) (fullsize path-string?) (thumbnail path-string?)
                                               (author-id exact-integer?)
                                               (title string?) (description string?)
                                               (tags (listof string?))
                                               (deleted? boolean?) (restricted? boolean?)
                                               (created-at datetime?)
                                               (bookmark (or/c boolean? null?)))])
 picture->hash/public
 user->hash/public)