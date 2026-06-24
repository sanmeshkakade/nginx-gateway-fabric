// Renders N HTTPRoute + SnippetsFilter pairs from route.yaml.tmpl to stdout.
// Usage: go run gen-routes.go [count] | kubectl apply -f -
package main

import (
	"os"
	"strconv"
	"text/template"
)

type route struct {
	Index     int
	Namespace string
	Gateway   string
	Backend   string
}

func main() {
	count := 60
	if len(os.Args) > 1 {
		n, err := strconv.Atoi(os.Args[1])
		if err != nil {
			panic(err)
		}
		count = n
	}

	tmpl := template.Must(template.ParseFiles("route.yaml.tmpl"))
	for i := 0; i < count; i++ {
		if err := tmpl.Execute(os.Stdout, route{Index: i, Namespace: "demo", Gateway: "gateway", Backend: "coffee"}); err != nil {
			panic(err)
		}
	}
}
