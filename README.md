# Contour
Contour is a web application, inspired by [Artstation](https://www.artstation.com/), which allows users to share their artworks with everyone. The "everyone" may be understood figuratively, but I also take pride in its more literal meaning - in the spirit of Progressive Enhancement, the basic functionality (that being viewing the pictures' gallery) uses no JavaScript, to ensure it does not stop anyone from accessing the website.

# Deployment
The Racket code depends on the following packages:
* [web-server](https://docs.racket-lang.org/web-server/index.html)
* [crypto](https://docs.racket-lang.org/crypto/index.html)
* [gregor](https://docs.racket-lang.org/gregor/index.html)
* [db](https://docs.racket-lang.org/db/index.html)
* [uuid](https://docs.racket-lang.org/uuid/index.html)

Once the dependencies are satisfied, the server may either be run directly on the computer, or packaged into a standalone executable and deployed to remote server.
