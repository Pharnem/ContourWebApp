#lang racket/base
(require racket/contract
         racket/function
         racket/path
         racket/set
         racket/string
         web-server/servlet
         uuid
         2htdp/image
         db
         "util.rkt"
         "data.rkt"
         "tags.rkt"
         "sql.rkt"
         "state.rkt")
(define (scale-to-fit bmp w h)
  (let ([ri (/ (image-width bmp) (image-height bmp))]
        [rs (/ w h)])
    (if (> rs ri)
        (scale (/ h (image-height bmp)) bmp)        
        (scale (/ w (image-width bmp)) bmp)
        )))

(define/contract (post-picture picture-data title description tags user-id)
  (-> bytes? string? string? (listof string?) exact-integer? exact-integer?)
  (let* ([file-uri (save-picture "images" picture-data)]
         [thumb-data (scale-to-fit (bitmap/file (content-uri->path file-uri)) 400 400)]
         [thumb-uri (save-picture "thumbnails" thumb-data)]
         [picture-id (sql:new-picture (conn/w) user-id file-uri thumb-uri title description)])
    (sql:assign-tags (conn/w) picture-id tags)
    picture-id))

(provide post-picture)