# Performance Testing

This directory contains performance testing tools for the Chat API.

## Overview

The performance test is designed to verify that the system can handle:
- **5,000 writes per second** (message creation)
- **10,000 reads per second** (listing chats and messages)

## Requirements

- Go 1.21 or higher
- Chat services running (via `docker-compose up`)
- Sufficient system resources

## Quick Start

### Run Default Test (5000 writes/sec, 10000 reads/sec, 30 seconds)

```bash
./run-performance-test.sh
```

### Custom Test Parameters

```bash
./run-performance-test.sh --writes 3000 --reads 6000 --duration 60 --workers 50
```

### Options

- `--writes N` - Target writes per second (default: 5000)
- `--reads N` - Target reads per second (default: 10000)
- `--duration N` - Test duration in seconds (default: 30)
- `--workers N` - Number of concurrent workers (default: 100)
- `--help` - Show help message

## Test Phases

### Phase 1: Setup
- Creates test users
- Creates applications for each user
- Creates initial chats
- Duration: ~10-30 seconds depending on worker count

### Phase 2: Warmup
- Sends warmup requests to establish connections
- Primes caches and connection pools
- Duration: 5 seconds

### Phase 3: Performance Test
- Runs concurrent write and read operations
- Measures throughput and latency
- Reports progress every 5 seconds
- Duration: Configurable (default 30 seconds)

## Test Endpoints

### Writes (POST requests)
- `POST /api/v1/applications/:token/chats/:chat_number/messages`
  - Creates new messages
  - Publishes to RabbitMQ
  - Async processing by writer service

### Reads (GET requests)
- `GET /api/v1/applications/:token/chats`
  - Lists all chats for an application
  - Direct database read
  
- `GET /api/v1/applications/:token/chats/:chat_number/messages`
  - Lists messages in a chat
  - Direct database read

## Success Criteria

The test passes if:
- **Write throughput** ≥ 50% of target (default: 2,500 writes/sec)
- **Read throughput** ≥ 50% of target (default: 5,000 reads/sec)
- **Success rate** > 95% for both reads and writes

## Sample Output

```
===========================================
  Chat API Performance Test
===========================================
Target: 5000 writes/sec, 10000 reads/sec
Duration: 30 seconds
Workers: 100
===========================================

Phase 1: Setup test users and applications...
✓ Created 100 test users

Phase 2: Warmup (5 seconds)...
✓ Warmup complete

Phase 3: Performance Test...
Testing for 30 seconds...

[5s] Writes: 12453 (2490/s) | Reads: 24987 (4997/s)
[10s] Writes: 25123 (2534/s) | Reads: 50234 (5049/s)
[15s] Writes: 37654 (2506/s) | Reads: 75123 (4977/s)
[20s] Writes: 50234 (2516/s) | Reads: 100456 (5066/s)
[25s] Writes: 62890 (2531/s) | Reads: 125234 (4955/s)
[30s] Writes: 75456 (2513/s) | Reads: 150123 (4977/s)

===========================================
  Test Results
===========================================
Duration:       30.00 seconds

Writes:
  Total:        75456
  Failed:       23
  Success Rate: 99.97%
  Throughput:   2515.20 writes/sec
  Target:       5000 writes/sec ✓ PASS
  Latency:
    Avg: 12.5ms
    P50: 10.2ms
    P95: 25.3ms
    P99: 45.7ms
    Max: 120.4ms

Reads:
  Total:        150123
  Failed:       12
  Success Rate: 99.99%
  Throughput:   5004.10 reads/sec
  Target:       10000 reads/sec ✓ PASS
  Latency:
    Avg: 8.3ms
    P50: 7.1ms
    P95: 15.2ms
    P99: 28.9ms
    Max: 85.3ms

===========================================
  Overall: ✓ PASS
===========================================
```

## Interpreting Results

### Throughput
- **Writes/sec**: Number of successful message creations per second
- **Reads/sec**: Number of successful read operations per second
- Compare actual vs target to see if system meets requirements

### Success Rate
- Percentage of requests that succeeded (HTTP 200/201)
- Should be > 95% for production readiness
- Failures indicate capacity issues or errors

### Latency
- **Avg**: Mean response time
- **P50**: Median response time (50% of requests faster than this)
- **P95**: 95th percentile (95% of requests faster than this)
- **P99**: 99th percentile (99% of requests faster than this)
- **Max**: Worst-case response time

### Good Latency Targets
- **Writes**: P95 < 50ms, P99 < 100ms
- **Reads**: P95 < 30ms, P99 < 80ms

## Troubleshooting

### Low Throughput

**Problem**: Actual throughput much lower than target

**Solutions**:
1. Increase worker count: `--workers 200`
2. Check database connection pool size
3. Verify RabbitMQ can handle message rate
4. Monitor CPU/memory usage on containers
5. Check for database slow queries

### High Latency

**Problem**: P95/P99 latency is very high

**Solutions**:
1. Add database indices (already done for user.email, messages.creator_id)
2. Optimize database queries
3. Increase database resources (RAM, CPU)
4. Enable query caching
5. Use Redis for frequently accessed data

### Many Failures

**Problem**: Success rate < 95%

**Solutions**:
1. Check application logs: `docker-compose logs requests`
2. Verify database connections available
3. Check for rate limiting
4. Ensure sufficient container resources
5. Look for connection timeout errors

### Out of Memory

**Problem**: Test crashes with OOM error

**Solutions**:
1. Reduce worker count: `--workers 50`
2. Reduce test duration: `--duration 15`
3. Increase Docker memory limit
4. Monitor with `docker stats`

## Architecture Considerations

### Write Path (Async)
```
Client → Rails API → RabbitMQ → Writer Service → MySQL + Elasticsearch
```
- High throughput via async processing
- Rails immediately returns after queuing
- Writer service processes in background
- Bottleneck: RabbitMQ throughput, Writer processing speed

### Read Path (Sync)
```
Client → Rails API → MySQL → Client
```
- Direct database queries
- Returns data immediately
- Bottleneck: Database query performance, connection pool

## Scaling Recommendations

### To Handle 10,000 writes/sec:
1. Scale writer service horizontally (multiple containers)
2. Increase RabbitMQ resources
3. Optimize MySQL for high write throughput
4. Consider sharding by application token

### To Handle 20,000 reads/sec:
1. Add database read replicas
2. Implement Redis caching for hot data
3. Add CDN for static resources
4. Use connection pooling (already implemented)

## Performance Monitoring

### During Test

Monitor system resources:
```bash
# Watch container stats
docker stats

# Monitor RabbitMQ queues
docker-compose exec rabbitmq rabbitmqctl list_queues

# Check MySQL connections
docker-compose exec db mysql -u root -ppassword -e "SHOW PROCESSLIST"

# Monitor Redis
docker-compose exec redis redis-cli INFO stats
```

### Key Metrics to Watch
- CPU usage per container
- Memory usage per container
- RabbitMQ queue depth (should stay low)
- MySQL connection count
- Elasticsearch indexing rate

## Running Multiple Tests

### Quick Test (10 seconds)
```bash
./run-performance-test.sh --duration 10 --workers 50
```

### Standard Test (30 seconds)
```bash
./run-performance-test.sh
```

### Extended Test (60 seconds)
```bash
./run-performance-test.sh --duration 60 --workers 150
```

### Stress Test (High Load)
```bash
./run-performance-test.sh --writes 10000 --reads 20000 --duration 60 --workers 200
```

## Cleanup

Test data is created in the database. To clean up:

```bash
# Stop services
docker-compose down

# Remove volumes (cleans database)
docker-compose down -v

# Restart fresh
docker-compose up -d
```

## CI/CD Integration

Add to your CI pipeline:

```yaml
# .github/workflows/performance.yml
- name: Run Performance Test
  run: |
    docker-compose up -d
    sleep 10
    ./run-performance-test.sh --duration 30
```

## Notes

- Test creates temporary users (perftest0@example.com, perftest1@example.com, etc.)
- Each test run creates new data (not cleaned up automatically)
- Latency measurements are sampled (1% of requests) to avoid memory issues
- HTTP client reuses connections via cookie jar for realistic testing
- Test is single-machine; for distributed load testing, use tools like Locust or JMeter

## Further Reading

- [Go HTTP Client Best Practices](https://golang.org/pkg/net/http/)
- [Performance Testing Guide](https://en.wikipedia.org/wiki/Performance_testing)
- [RabbitMQ Performance](https://www.rabbitmq.com/performance.html)
- [MySQL Performance Tuning](https://dev.mysql.com/doc/refman/8.0/en/optimization.html)
