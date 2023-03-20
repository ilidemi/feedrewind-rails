package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"sort"
	"strings"

	"github.com/antchfx/htmlquery"
	"github.com/mmcdole/gofeed"
	"golang.org/x/net/html"
)

var blockedHosts = make(map[string]bool)

func init() {
	blockedHosts["www.youtube.com"] = true
	blockedHosts["github.com"] = true
	blockedHosts["youtu.be"] = true
	blockedHosts["twitter.com"] = true
	blockedHosts["www.amazon.com"] = true
	blockedHosts["gist.github.com"] = true
	blockedHosts["randygaul.net"] = true
	blockedHosts["www.randygaul.net"] = true
	blockedHosts["en.wikipedia.org"] = true
	blockedHosts["reddit.com"] = true
	blockedHosts["www.reddit.com"] = true
	blockedHosts["aggregate.org"] = true
	blockedHosts["elm-chan.org"] = true
	blockedHosts["queue.acm.org"] = true
}

func main() {
	statFilename := "feeds_vm.csv"
	if _, err := os.Stat(statFilename); err == nil {
		stat(statFilename)
	} else {
		download()
	}
}

func download() {
	jsonBytes, err := os.ReadFile("the-library.json")
	if err != nil {
		panic(err)
	}

	var root map[string]interface{}
	if err := json.Unmarshal(jsonBytes, &root); err != nil {
		panic(err)
	}

	messages := root["messages"].([]interface{})
	regex := regexp.MustCompile("https?://[^\\s]+")
	countsByLink := make(map[string]int)
	messageIdsByLink := make(map[string][]string)
	for _, message := range messages {
		messageId := message.(map[string]interface{})["id"].(string)
		content := message.(map[string]interface{})["content"].(string)
		matches := regex.FindAllStringIndex(content, -1)
		if len(matches) > 0 {
			for _, match := range matches {
				link := content[match[0]:match[1]]
				if link[len(link)-1] == '.' {
					link = link[:len(link)-1]
				}
				if link[len(link)-1] == ',' {
					link = link[:len(link)-1]
				}
				if link[len(link)-1] == ')' &&
					(strings.Count(link, ")")-strings.Count(link, "(") == 1) {
					link = link[:len(link)-1]
				}
				if link[len(link)-1] == '>' &&
					(strings.Count(link, ">")-strings.Count(link, "<") == 1) {
					link = link[:len(link)-1]
				}

				countsByLink[link]++
				messageIdsByLink[link] = append(messageIdsByLink[link], messageId)
			}
		}
	}

	linksByDomain := make(map[string][]string)
	linksToProcess := 0
	for link := range countsByLink {
		linkUrl, _ := url.Parse(link)
		if err != nil {
			panic(err)
		}

		if _, ok := blockedHosts[linkUrl.Host]; ok {
			continue
		}

		linksByDomain[linkUrl.Host] = append(linksByDomain[linkUrl.Host], link)
		linksToProcess++
	}

	totalFeeds := 0

	ch := make(chan FindResult)
	for _, domainLinks := range linksByDomain {
		go batchFindFeedLinksRecursively(domainLinks, ch)
	}

	outFile, err := os.Create("feeds.csv")
	if err != nil {
		panic(err)
	}
	defer outFile.Close()

	for i := 0; i < linksToProcess; i++ {
		result := <-ch
		fmt.Printf("%d/%d\n", i+1, linksToProcess)

		if result.err != nil {
			fmt.Printf("%s %s\n", result.link, result.err)
			continue
		}

		fmt.Printf("%s has %d feeds", result.link, len(result.feedLinks))
		if result.feedFoundAt != "" {
			fmt.Printf(" (found at %s)", result.feedFoundAt)
		}
		fmt.Println()

		if len(result.feedLinks) > 0 {
			fmt.Fprintf(
				outFile, "%s\t%d\t%s\t%s",
				result.link, len(result.feedLinks), messageIdsByLink[result.link], result.feedFoundAt,
			)

			for _, feedLink := range result.feedLinks {
				fmt.Fprintf(outFile, "\t%s", feedLink)
			}
			fmt.Fprintln(outFile)
		}

		totalFeeds += len(result.feedLinks)
	}

	fmt.Printf("Total feeds: %d\n", totalFeeds)
}

type FindResult struct {
	link        string
	feedFoundAt string
	feedLinks   []string
	err         error
}

func batchFindFeedLinksRecursively(links []string, ch chan<- FindResult) {
	for _, link := range links {
		findFeedLinksRecursively(link, ch)
	}
}

func findFeedLinksRecursively(link string, ch chan<- FindResult) {
	currentLink := link
	for strings.Count(currentLink, "/") > 2 {
		feedLinks, err := findFeedLinks(currentLink)
		if err != nil {
			ch <- FindResult{link: link, err: err}
			return
		}

		if len(feedLinks) > 0 {
			ch <- FindResult{link: link, feedFoundAt: currentLink, feedLinks: feedLinks}
			return
		}

		lastSlashIndex := strings.LastIndex(currentLink[:len(currentLink)-1], "/")
		currentLink = currentLink[:lastSlashIndex]
	}

	ch <- FindResult{link: link, feedLinks: nil}
	return
}

var (
	feedBurnerRegex1 = regexp.MustCompile(`/[^/]+\.(?:xml|rss|atom)$`)
	feedBurnerRegex2 = regexp.MustCompile(`/(?:feed|rss|atom)$`)
	feedBurnerRegex3 = regexp.MustCompile(`/(?:feeds?|rss|atom)/`)
)

func findFeedLinks(link string) ([]string, error) {
	linkUrl, err := url.Parse(link)
	if err != nil {
		return nil, err
	}

	resp, err := http.Get(link)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.Status[0] != '2' {
		if resp.Status[0] == '3' {
			panic(fmt.Sprintf("Redirects not handled: %s", link))
		}

		return nil, errors.New(fmt.Sprintf("Status %s", resp.Status))
	}

	contentType := resp.Header.Get("content-type")
	if contentType == "" || strings.Split(contentType, ";")[0] != "text/html" {
		return nil, errors.New("Not a html")
	}

	doc, err := html.Parse(resp.Body)
	if err != nil {
		return nil, err
	}
	nodes, err := htmlquery.QueryAll(doc, "/html/head/link[@rel='alternate']")
	if err != nil {
		return nil, errors.New("Couldn't query alternate links")
	}

	var feedLinks []string
	for _, node := range nodes {
		isRssOrAtom := false
		for _, attr := range node.Attr {
			if attr.Key == "type" &&
				(attr.Val == "application/rss+xml" || attr.Val == "application/atom+xml") {
				isRssOrAtom = true
				break
			}
		}

		if !isRssOrAtom {
			continue
		}

		var href string
		for _, attr := range node.Attr {
			if attr.Key == "href" {
				href = attr.Val
				break
			}
		}
		if href == "" {
			continue
		}

		if strings.HasSuffix(href, "?alt=rss") {
			continue
		}

		if strings.HasSuffix(href, "/comments/feed/") {
			continue
		}

		if strings.HasSuffix(href, "/comments/feed") {
			continue
		}

		if strings.HasSuffix(href, "/comments/default") {
			continue
		}

		hrefUrl, err := url.Parse(href)
		if err != nil {
			continue
		}

		fullUrl := linkUrl.ResolveReference(hrefUrl)
		if fullUrl.Scheme != "http" && fullUrl.Scheme != "https" {
			continue
		}

		feedLinks = append(feedLinks, fullUrl.String())
	}

	linkNodes, err := htmlquery.QueryAll(doc, "//a")
	if err != nil {
		return nil, errors.New("Couldn't query all links")
	}

	for _, linkNode := range linkNodes {
		var href string
		for _, attr := range linkNode.Attr {
			if attr.Key == "href" {
				href = attr.Val
				break
			}
		}
		if href == "" {
			continue
		}

		linkUrl, err := url.Parse(href)
		if err != nil {
			continue
		}

		if linkUrl.Host != "feeds.feedburner.com" {
			continue
		}

		if feedBurnerRegex1.MatchString(href) ||
			feedBurnerRegex2.MatchString(href) ||
			feedBurnerRegex3.MatchString(href) {
			feedLinks = append(feedLinks, href)
		}
	}

	var validFeedLinks []string
	for _, feedLink := range feedLinks {
		resp, err := http.Get(feedLink)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Feed fetch error: %s (%v)\n", feedLink, err)
			continue
		}
		defer resp.Body.Close()

		if resp.Status[0] == '3' {
			panic(fmt.Sprintf("Redirects not handled: %s", link))
		}

		bodyBytes, err := ioutil.ReadAll(resp.Body)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Feed body fetch error: %s (%v)\n", feedLink, err)
			continue
		}

		feedParser := gofeed.NewParser()
		_, err = feedParser.Parse(bytes.NewReader(bodyBytes))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Feed body parse error: %s (%v)\n", feedLink, err)
			continue
		}

		validFeedLinks = append(validFeedLinks, feedLink)
	}

	return validFeedLinks, nil
}

type FeedStat struct {
	link       string
	messageIds map[string]bool
	links      map[string]bool
}

func stat(filename string) {
	ppFile, err := os.Open("postprocess_feeds.txt")
	if err != nil {
		panic(err)
	}
	defer ppFile.Close()

	filteredOutUrls := make(map[string]bool)
	filteredOutPrefixes := []string{}
	replacements := make(map[string]string)

	ppScanner := bufio.NewScanner(ppFile)
	for ppScanner.Scan() {
		line := ppScanner.Text()
		arrow := " -> "
		if strings.HasSuffix(line, "*") {
			filteredOutPrefixes = append(filteredOutPrefixes, line[:len(line)-1])
		} else if arrowIdx := strings.Index(line, arrow); arrowIdx != -1 {
			from := line[:arrowIdx]
			to := line[arrowIdx+len(arrow):]
			replacements[from] = to
		} else {
			filteredOutUrls[line] = true
		}
	}

	inFile, err := os.Open(filename)
	if err != nil {
		panic(err)
	}
	defer inFile.Close()

	scanner := bufio.NewScanner(inFile)
	var shortFeedLinks []string
	statsByShortFeedLink := make(map[string]*FeedStat)
	for scanner.Scan() {
		line := scanner.Text()
		row := strings.Split(line, "\t")

		link := row[0]
		messageIdsStr := row[2]
		feedLink := row[4]
		messageIds := strings.Split(messageIdsStr[1:len(messageIdsStr)-1], ",")

		shortFeedLink := strings.TrimPrefix(strings.TrimPrefix(feedLink, "http://"), "https://")

		if _, ok := statsByShortFeedLink[shortFeedLink]; !ok {
			shortFeedLinks = append(shortFeedLinks, shortFeedLink)
			statsByShortFeedLink[shortFeedLink] = new(FeedStat)
			statsByShortFeedLink[shortFeedLink].link = feedLink
			statsByShortFeedLink[shortFeedLink].messageIds = make(map[string]bool)
			statsByShortFeedLink[shortFeedLink].links = make(map[string]bool)
		}

		feedStat := statsByShortFeedLink[shortFeedLink]
		for _, messageId := range messageIds {
			feedStat.messageIds[messageId] = true
		}
		feedStat.links[link] = true
	}

	sort.SliceStable(shortFeedLinks, func(i, j int) bool {
		return len(statsByShortFeedLink[shortFeedLinks[i]].messageIds) >
			len(statsByShortFeedLink[shortFeedLinks[j]].messageIds)
	})

	outFile, err := os.Create("feed_stats.csv")
	if err != nil {
		panic(err)
	}
	defer outFile.Close()

outer:
	for _, shortFeedLink := range shortFeedLinks {
		feedStat := statsByShortFeedLink[shortFeedLink]

		if _, ok := filteredOutUrls[feedStat.link]; ok {
			continue
		}

		for _, prefix := range filteredOutPrefixes {
			if strings.HasPrefix(feedStat.link, prefix) {
				continue outer
			}
		}

		feedLink := feedStat.link
		if replacement, ok := replacements[feedStat.link]; ok {
			feedLink = replacement
		}

		fmt.Fprintf(outFile, "%s\t%d\t%d", feedLink, len(feedStat.messageIds), len(feedStat.links))
		for link := range feedStat.links {
			fmt.Fprintf(outFile, "\t%s", link)
		}
		fmt.Fprintln(outFile)
	}
}
