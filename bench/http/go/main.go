// net/http: the idiomatic Go server. Goroutine per connection, keep-alive on.
package main

import (
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		w.Header().Set("Content-Length", "13")
		w.Write([]byte("hello, world\n"))
	})
	http.ListenAndServe("127.0.0.1:"+os.Args[1], nil)
}
