package main

import (
	"encoding/csv"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
)

func main() {
	inFile, err := os.Open("urls.csv")
	if err != nil {
		panic(err)
	}

	sumScoresByRootUrl := make(map[string]int)

	reader := csv.NewReader(inFile)
	reader.Read() // header
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			panic(err)
		}

		url := record[0]
		score, err := strconv.ParseInt(record[1], 10, 32)
		if err != nil {
			panic(err)
		}

		pathStart := strings.Index(url, "/p/")
		rootUrl := url[:pathStart]

		sumScoresByRootUrl[rootUrl] += int(score)
	}

	inFile.Close()

	ch := make(chan Result)
	for rootUrl := range sumScoresByRootUrl {
		go checkIfSubstack(rootUrl, ch)
	}

	var substackRootUrls []string
	rootUrlCount := len(sumScoresByRootUrl)
	for i := 0; i < rootUrlCount; i++ {
		result := <-ch
		status := "is not substack"
		if result.err != nil {
			status = fmt.Sprintf("is error %s", result.err)
		} else if result.isSubstack {
			status = "is substack"
			substackRootUrls = append(substackRootUrls, result.rootUrl)
		}
		fmt.Printf("%s %s (%d/%d)\n", result.rootUrl, status, i+1, rootUrlCount)
	}

	// sort descending
	sort.SliceStable(substackRootUrls, func(i, j int) bool {
		return sumScoresByRootUrl[substackRootUrls[i]] > sumScoresByRootUrl[substackRootUrls[j]]
	})

	outFile, err := os.Create("substack_urls.csv")
	if err != nil {
		panic(err)
	}

	writer := csv.NewWriter(outFile)
	writer.Write([]string{"root_url", "sum_score"})
	for _, substackRootUrl := range substackRootUrls {
		sumScore := fmt.Sprint(sumScoresByRootUrl[substackRootUrl])
		writer.Write([]string{substackRootUrl, sumScore})
	}
	writer.Flush()

	outFile.Close()
}

type Result struct {
	rootUrl    string
	isSubstack bool
	err        error
}

func checkIfSubstack(rootUrl string, ch chan Result) {
	resp, err := http.Get(rootUrl)
	if err != nil {
		ch <- Result{rootUrl, false, err}
		return
	}
	defer resp.Body.Close()

	bodyBytes, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		ch <- Result{rootUrl, false, err}
		return
	}

	body := string(bodyBytes)
	isSubstack := strings.Contains(body, `<link rel="shortcut icon" href="https://substackcdn.com/`)
	ch <- Result{rootUrl, isSubstack, nil}
}
