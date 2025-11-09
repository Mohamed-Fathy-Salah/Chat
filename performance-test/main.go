package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"net/http/cookiejar"
	"sync"
	"sync/atomic"
	"time"
)

var (
	baseURL        = "http://localhost:3000/api/v1"
	writeTarget    = 5000  // writes per second
	readTarget     = 10000 // reads per second
	testDuration   = 30    // seconds
	concurrency    = 100   // concurrent workers
	
	totalWrites   int64
	totalReads    int64
	failedWrites  int64
	failedReads   int64
	writeLatencies []time.Duration
	readLatencies  []time.Duration
	latencyMutex   sync.Mutex
)

type TestUser struct {
	Email    string
	Password string
	Token    string
	Client   *http.Client
	ChatNum  int
}

func main() {
	flag.IntVar(&writeTarget, "writes", 5000, "Target writes per second")
	flag.IntVar(&readTarget, "reads", 10000, "Target reads per second")
	flag.IntVar(&testDuration, "duration", 30, "Test duration in seconds")
	flag.IntVar(&concurrency, "workers", 100, "Number of concurrent workers")
	flag.Parse()

	fmt.Println("===========================================")
	fmt.Println("  Chat API Performance Test")
	fmt.Println("===========================================")
	fmt.Printf("Target: %d writes/sec, %d reads/sec\n", writeTarget, readTarget)
	fmt.Printf("Duration: %d seconds\n", testDuration)
	fmt.Printf("Workers: %d\n", concurrency)
	fmt.Println("===========================================\n")

	// Setup phase
	fmt.Println("Phase 1: Setup test users and applications...")
	users := setupTestUsers(concurrency)
	fmt.Printf("✓ Created %d test users\n\n", len(users))

	// Warmup phase
	fmt.Println("Phase 2: Warmup (5 seconds)...")
	warmup(users)
	fmt.Println("✓ Warmup complete\n")

	// Performance test phase
	fmt.Println("Phase 3: Performance Test...")
	fmt.Printf("Testing for %d seconds...\n\n", testDuration)
	
	startTime := time.Now()
	
	var wg sync.WaitGroup
	stopChan := make(chan struct{})

	// Start write workers
	writeWorkersCount := concurrency / 2
	for i := 0; i < writeWorkersCount; i++ {
		wg.Add(1)
		go writeWorker(users[i%len(users)], stopChan, &wg)
	}

	// Start read workers
	readWorkersCount := concurrency - writeWorkersCount
	for i := 0; i < readWorkersCount; i++ {
		wg.Add(1)
		go readWorker(users[i%len(users)], stopChan, &wg)
	}

	// Progress reporter
	go progressReporter(startTime, stopChan)

	// Run test for specified duration
	time.Sleep(time.Duration(testDuration) * time.Second)
	close(stopChan)
	wg.Wait()

	duration := time.Since(startTime)

	// Results
	fmt.Println("\n===========================================")
	fmt.Println("  Test Results")
	fmt.Println("===========================================")
	
	printResults(duration)
}

func setupTestUsers(count int) []*TestUser {
	users := make([]*TestUser, count)
	
	for i := 0; i < count; i++ {
		email := fmt.Sprintf("perftest%d@example.com", i)
		password := "password123"
		
		jar, _ := cookiejar.New(nil)
		client := &http.Client{
			Jar:     jar,
			Timeout: 10 * time.Second,
		}

		// Register
		registerData := map[string]string{
			"name":                  fmt.Sprintf("Perf User %d", i),
			"email":                 email,
			"password":              password,
			"password_confirmation": password,
		}
		
		jsonData, _ := json.Marshal(registerData)
		req, _ := http.NewRequest("POST", baseURL+"/auth/register", bytes.NewBuffer(jsonData))
		req.Header.Set("Content-Type", "application/json")
		client.Do(req)

		// Login
		loginData := map[string]string{
			"email":    email,
			"password": password,
		}
		jsonData, _ = json.Marshal(loginData)
		req, _ = http.NewRequest("POST", baseURL+"/auth/login", bytes.NewBuffer(jsonData))
		req.Header.Set("Content-Type", "application/json")
		client.Do(req)

		// Create application
		appData := map[string]string{
			"name": fmt.Sprintf("Perf App %d", i),
		}
		jsonData, _ = json.Marshal(appData)
		req, _ = http.NewRequest("POST", baseURL+"/applications", bytes.NewBuffer(jsonData))
		req.Header.Set("Content-Type", "application/json")
		resp, _ := client.Do(req)
		
		var appResp map[string]string
		json.NewDecoder(resp.Body).Decode(&appResp)
		resp.Body.Close()

		// Create chat
		req, _ = http.NewRequest("POST", baseURL+"/applications/"+appResp["token"]+"/chats", nil)
		resp, _ = client.Do(req)
		
		var chatResp map[string]int
		json.NewDecoder(resp.Body).Decode(&chatResp)
		resp.Body.Close()

		users[i] = &TestUser{
			Email:    email,
			Password: password,
			Token:    appResp["token"],
			Client:   client,
			ChatNum:  chatResp["chatNumber"],
		}
	}

	return users
}

func warmup(users []*TestUser) {
	// Warm up with some requests
	for i := 0; i < 100; i++ {
		user := users[i%len(users)]
		
		// Create a message
		msgData := map[string]string{
			"body": fmt.Sprintf("Warmup message %d", i),
		}
		jsonData, _ := json.Marshal(msgData)
		url := fmt.Sprintf("%s/applications/%s/chats/%d/messages", baseURL, user.Token, user.ChatNum)
		req, _ := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
		req.Header.Set("Content-Type", "application/json")
		user.Client.Do(req)

		// Read messages
		url = fmt.Sprintf("%s/applications/%s/chats/%d/messages", baseURL, user.Token, user.ChatNum)
		req, _ = http.NewRequest("GET", url, nil)
		user.Client.Do(req)
	}
}

func writeWorker(user *TestUser, stop <-chan struct{}, wg *sync.WaitGroup) {
	defer wg.Done()

	// Calculate requests per worker: total target / number of write workers
	writeWorkers := concurrency / 2
	requestsPerWorker := writeTarget / writeWorkers
	if requestsPerWorker < 1 {
		requestsPerWorker = 1
	}
	interval := time.Second / time.Duration(requestsPerWorker)
	
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			start := time.Now()
			
			msgData := map[string]string{
				"body": fmt.Sprintf("Performance test message at %d", time.Now().UnixNano()),
			}
			jsonData, _ := json.Marshal(msgData)
			
			url := fmt.Sprintf("%s/applications/%s/chats/%d/messages", baseURL, user.Token, user.ChatNum)
			req, _ := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
			req.Header.Set("Content-Type", "application/json")
			
			resp, err := user.Client.Do(req)
			latency := time.Since(start)
			
			if err != nil || resp.StatusCode != 200 {
				atomic.AddInt64(&failedWrites, 1)
			} else {
				atomic.AddInt64(&totalWrites, 1)
				recordLatency(&writeLatencies, latency)
			}
			
			if resp != nil {
				io.Copy(io.Discard, resp.Body)
				resp.Body.Close()
			}
		}
	}
}

func readWorker(user *TestUser, stop <-chan struct{}, wg *sync.WaitGroup) {
	defer wg.Done()

	// Calculate requests per worker: total target / number of read workers
	readWorkers := concurrency - (concurrency / 2)
	requestsPerWorker := readTarget / readWorkers
	if requestsPerWorker < 1 {
		requestsPerWorker = 1
	}
	interval := time.Second / time.Duration(requestsPerWorker)
	
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	endpoints := []string{
		fmt.Sprintf("/applications/%s/chats", user.Token),
		fmt.Sprintf("/applications/%s/chats/%d/messages", user.Token, user.ChatNum),
	}

	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			start := time.Now()
			
			url := baseURL + endpoints[rand.Intn(len(endpoints))]
			req, _ := http.NewRequest("GET", url, nil)
			
			resp, err := user.Client.Do(req)
			latency := time.Since(start)
			
			if err != nil || resp.StatusCode != 200 {
				atomic.AddInt64(&failedReads, 1)
			} else {
				atomic.AddInt64(&totalReads, 1)
				recordLatency(&readLatencies, latency)
			}
			
			if resp != nil {
				io.Copy(io.Discard, resp.Body)
				resp.Body.Close()
			}
		}
	}
}

func recordLatency(latencies *[]time.Duration, latency time.Duration) {
	// Sample only 1% of requests to avoid memory issues
	if rand.Intn(100) == 0 {
		latencyMutex.Lock()
		*latencies = append(*latencies, latency)
		latencyMutex.Unlock()
	}
}

func progressReporter(startTime time.Time, stop <-chan struct{}) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	lastWrites := int64(0)
	lastReads := int64(0)

	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			elapsed := time.Since(startTime).Seconds()
			currentWrites := atomic.LoadInt64(&totalWrites)
			currentReads := atomic.LoadInt64(&totalReads)
			
			writesPerSec := float64(currentWrites-lastWrites) / 5.0
			readsPerSec := float64(currentReads-lastReads) / 5.0
			
			fmt.Printf("[%.0fs] Writes: %d (%.0f/s) | Reads: %d (%.0f/s)\n",
				elapsed, currentWrites, writesPerSec, currentReads, readsPerSec)
			
			lastWrites = currentWrites
			lastReads = currentReads
		}
	}
}

func printResults(duration time.Duration) {
	writes := atomic.LoadInt64(&totalWrites)
	reads := atomic.LoadInt64(&totalReads)
	failedW := atomic.LoadInt64(&failedWrites)
	failedR := atomic.LoadInt64(&failedReads)

	seconds := duration.Seconds()

	fmt.Printf("Duration:       %.2f seconds\n\n", seconds)

	fmt.Println("Writes:")
	fmt.Printf("  Total:        %d\n", writes)
	fmt.Printf("  Failed:       %d\n", failedW)
	fmt.Printf("  Success Rate: %.2f%%\n", float64(writes)/float64(writes+failedW)*100)
	fmt.Printf("  Throughput:   %.2f writes/sec\n", float64(writes)/seconds)
	if writes >= int64(writeTarget)*int64(testDuration)/2 {
		fmt.Printf("  Target:       %d writes/sec ✓ PASS\n", writeTarget)
	} else {
		fmt.Printf("  Target:       %d writes/sec ✗ FAIL\n", writeTarget)
	}

	if len(writeLatencies) > 0 {
		fmt.Printf("  Latency:\n")
		printLatencyStats(writeLatencies)
	}

	fmt.Println("\nReads:")
	fmt.Printf("  Total:        %d\n", reads)
	fmt.Printf("  Failed:       %d\n", failedR)
	fmt.Printf("  Success Rate: %.2f%%\n", float64(reads)/float64(reads+failedR)*100)
	fmt.Printf("  Throughput:   %.2f reads/sec\n", float64(reads)/seconds)
	if reads >= int64(readTarget)*int64(testDuration)/2 {
		fmt.Printf("  Target:       %d reads/sec ✓ PASS\n", readTarget)
	} else {
		fmt.Printf("  Target:       %d reads/sec ✗ FAIL\n", readTarget)
	}

	if len(readLatencies) > 0 {
		fmt.Printf("  Latency:\n")
		printLatencyStats(readLatencies)
	}

	fmt.Println("\n===========================================")
	
	writeThroughput := float64(writes) / seconds
	readThroughput := float64(reads) / seconds
	
	if writeThroughput >= float64(writeTarget)*0.5 && readThroughput >= float64(readTarget)*0.5 {
		fmt.Println("  Overall: ✓ PASS")
	} else {
		fmt.Println("  Overall: ✗ FAIL")
	}
	fmt.Println("===========================================")
}

func printLatencyStats(latencies []time.Duration) {
	if len(latencies) == 0 {
		return
	}

	// Sort latencies
	sorted := make([]time.Duration, len(latencies))
	copy(sorted, latencies)
	
	// Simple bubble sort (good enough for sampled data)
	for i := 0; i < len(sorted); i++ {
		for j := i + 1; j < len(sorted); j++ {
			if sorted[i] > sorted[j] {
				sorted[i], sorted[j] = sorted[j], sorted[i]
			}
		}
	}

	sum := time.Duration(0)
	for _, l := range sorted {
		sum += l
	}
	avg := sum / time.Duration(len(sorted))

	p50 := sorted[len(sorted)*50/100]
	p95 := sorted[len(sorted)*95/100]
	p99 := sorted[len(sorted)*99/100]

	fmt.Printf("    Avg: %v\n", avg)
	fmt.Printf("    P50: %v\n", p50)
	fmt.Printf("    P95: %v\n", p95)
	fmt.Printf("    P99: %v\n", p99)
	fmt.Printf("    Max: %v\n", sorted[len(sorted)-1])
}
