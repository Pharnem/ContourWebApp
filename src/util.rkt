#lang racket/base
(require (for-syntax
          racket/base
          syntax/parse)
         racket/contract
         racket/match
         racket/dict
         racket/path
         racket/function
         json
         xml
         xml/path
         uuid
         web-server/servlet
         syntax/parse/define
         2htdp/image
         "state.rkt"
         "data.rkt")

(define-syntax (failsafe stx)
  (syntax-parse stx
    [(_ (~literal all) (~optional (~seq #:on-fail resp) #:defaults ([resp #'(response/jsexpr (hash 'error #t 'status "Unknown error occured.") #:code 400)])) body ...)
     #'(with-handlers ([exn:fail? (λ (e)
                                    resp)])
         body ...)]
    [(_ (~literal user) (~optional (~seq #:on-fail resp) #:defaults ([resp #'(response/jsexpr (hash 'error #t 'status "Unauthorized.") #:code 401)])) body ...)
     #'(with-handlers ([exn:fail? (λ (e)
                                    resp)])
         (if (session-user)
             (begin
               body ...)
             resp))]
    [(_ (~literal manager) (~optional (~seq #:on-fail resp) #:defaults ([resp #'(response/jsexpr (hash 'error #t 'status "Unauthorized.") #:code 401)])) body ...)
     #'(with-handlers ([exn:fail? (λ (e)
                                    resp)])
         (if (and (session-user) (user-manager? (session-user)))
             (begin
               body ...)
             resp))]
    [(_ (~literal admin) (~optional (~seq #:on-fail resp) #:defaults ([resp #'(response/jsexpr (hash 'error #t 'status "Unauthorized.") #:code 401)])) body ...)
     #'(with-handlers ([exn:fail? (λ (e)
                                    resp)])
         (if (and (session-user) (user-admin? (session-user)))
             (begin
               body ...)
             resp))]
    ))

(define/contract (bytes->format b)
  (-> bytes? (or/c 'gif 'jpg 'png 'webp #f))
  (cond
    [(and (bytes=? (list->bytes '(#xFF #xD8)) (subbytes b 0 2)) (bytes=? (list->bytes '(#xFF #xD9)) (subbytes b (- (bytes-length b) 2) (bytes-length b)))) 'jpg]
    [(bytes=? (list->bytes '(#x89 #x50 #x4E #x47 #x0D #x0A #x1A #x0A)) (subbytes b 0 8)) 'png]
    [(and (>= (bytes-length b) 12) (bytes=? (list->bytes '(#x52 #x49 #x46 #x46)) (subbytes b 0 4)) (bytes=? (list->bytes '(#x57 #x45 #x42 #x50)) (subbytes b 8 12))) 'webp]
    [else #f]))

(define/contract (format->extension format)
  (-> (or/c 'jpg 'png 'webp) string?)
  (match format
    ['jpg ".jpg"]
    ['png ".png"]
    ['webp ".webp"]))

(define/contract (save-picture directory file-contents)
  (-> string? (or/c bytes? image?) (or/c string? #f))
  (define fmt (if (image? file-contents) 'png (bytes->format file-contents)))
  (if fmt
      (let*
          ([filename (string-append (uuid-string) (format->extension fmt))]
           [file-uri (string-append
                      "/" directory "/"
                      filename)]
           [file-path (string-append "content" file-uri)])
        (match file-contents
          [(? bytes? bytedata)
           (with-output-to-file file-path
             #:exists 'error
             (thunk
              (display bytedata)))]
          [(? image? img)
           (save-image file-contents file-path)])
        file-uri)
      #f))

(define/contract (content-uri->path uri)
  (-> string? string?)
  (string-append "content" uri))

(define/contract (get-referer req)
  (-> request? string?)
  (bytes->string/utf-8 (header-value (or (headers-assq* #"Referer" (request-headers/raw req)) (header #"Referer" #"/")))))

(define/contract (extract-form-value id [default #f])
  (->* [bytes?] [any/c] any/c)
  (define temp (bindings-assq id (bindings)))
  (if temp
      (if (binding:file? temp)
          (binding:file-content temp)
          (bytes->string/utf-8 (binding:form-value temp)))
      default))

(define/contract (bytes->number bstr)
  (-> bytes? number?)
  (string->number (bytes->string/utf-8 bstr)))

(define/contract (extract-data req keys)
  (-> request? (listof symbol?) (->* [symbol?] [any/c] any/c))
  (define d (match (content-type)
              ('json (hash->list (bytes->jsexpr (request-post-data/raw req))))
              ('xml (let ([doc (string->xexpr (bytes->string/utf-8 (request-post-data/raw req)))])
                      (for/list ([key keys])
                        (cons key (se-path* (list key) doc)))))
              ('default (for/list ([key keys])
                          (cons key (extract-form-value (string->bytes/utf-8 (symbol->string key))))))))
  (λ (key [default #f]) (or (dict-ref d key) default)))

(provide save-picture
         content-uri->path
         get-referer
         extract-form-value
         bytes->number
         extract-data
         failsafe)