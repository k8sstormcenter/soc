package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"time"

	"github.com/ClickHouse/clickhouse-go/v2"
	"px.dev/pixie/src/api/go/pxapi"
	"px.dev/pixie/src/api/go/pxapi/types"
)

var (
	pxAPIKey     = mustEnv("PX_API_KEY")
	pxCloudAddr  = envOr("PX_CLOUD_ADDR", "pixie.austrianopencloudcommunity.org")
	pxClusterID  = mustEnv("PX_CLUSTER_ID")
	chHost       = envOr("CH_HOST", "localhost")
	chPort       = envOrInt("CH_PORT", 9000)
	chUser       = envOr("CH_USER", "forensic_analyst")
	chPass       = envOr("CH_PASS", "changeme-analyst")
	chDB         = envOr("CH_DB", "forensic_db")
	chExportHost = envOr("CH_EXPORT_HOST", "clickhouse-forensic-soc-db.clickhouse.svc.cluster.local")
	chExportUser = envOr("CH_INGEST_USER", "ingest_writer")
	chExportPass = envOr("CH_INGEST_PASS", "changeme-ingest")
	pollInterval = envOrInt("POLL_INTERVAL", 10)
	exportWindow = envOrInt("EXPORT_WINDOW", 300)
	cooldown     = envOrInt("COOLDOWN", 600)
)

var tables = []string{"http_events", "dns_events", "conn_stats", "process_stats", "network_stats"}

type podKey struct {
	Namespace string
	Pod       string
}

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()

	exportDSN := fmt.Sprintf("%s:%s@%s:%d/%s", chExportUser, chExportPass, chExportHost, chPort, chDB)
	log.Printf("pixie cluster=%s cloud=%s", pxClusterID, pxCloudAddr)
	log.Printf("clickhouse read=%s@%s:%d/%s", chUser, chHost, chPort, chDB)
	log.Printf("clickhouse export DSN=%s", exportDSN)
	log.Printf("poll=%ds window=%ds cooldown=%ds", pollInterval, exportWindow, cooldown)

	// ClickHouse reader connection
	chConn, err := clickhouse.Open(&clickhouse.Options{
		Addr: []string{fmt.Sprintf("%s:%d", chHost, chPort)},
		Auth: clickhouse.Auth{Database: chDB, Username: chUser, Password: chPass},
	})
	if err != nil {
		log.Fatalf("clickhouse connect: %v", err)
	}
	if err := chConn.Ping(ctx); err != nil {
		log.Fatalf("clickhouse ping: %v", err)
	}

	// Pixie client
	pxClient, err := pxapi.NewClient(ctx, pxapi.WithAPIKey(pxAPIKey), pxapi.WithCloudAddr(pxCloudAddr))
	if err != nil {
		log.Fatalf("pixie client: %v", err)
	}
	vz, err := pxClient.NewVizierClient(ctx, pxClusterID)
	if err != nil {
		log.Fatalf("pixie vizier client: %v", err)
	}

	var mu sync.Mutex
	exported := map[podKey]time.Time{}

	ticker := time.NewTicker(time.Duration(pollInterval) * time.Second)
	defer ticker.Stop()

	log.Println("running")
	for {
		select {
		case <-ctx.Done():
			log.Println("shutting down")
			return
		case <-ticker.C:
			pods := pollAnomalies(ctx, chConn)
			for _, pk := range pods {
				mu.Lock()
				last, seen := exported[pk]
				cooledDown := !seen || time.Since(last) > time.Duration(cooldown)*time.Second
				if cooledDown {
					exported[pk] = time.Now()
				}
				mu.Unlock()
				if !cooledDown {
					continue
				}
				log.Printf("exporting %s/%s", pk.Namespace, pk.Pod)
				go exportPod(ctx, vz, exportDSN, pk)
			}
		}
	}
}

func pollAnomalies(ctx context.Context, conn clickhouse.Conn) []podKey {
	query := fmt.Sprintf(`
		SELECT DISTINCT
			JSONExtractString(RuntimeK8sDetails, 'podNamespace') AS ns,
			JSONExtractString(RuntimeK8sDetails, 'podName') AS pod
		FROM %s.kubescape_logs
		WHERE event_time > (toUnixTimestamp(now()) - %d)
		  AND ns != '' AND pod != ''
	`, chDB, pollInterval*2)

	rows, err := conn.Query(ctx, query)
	if err != nil {
		log.Printf("poll error: %v", err)
		return nil
	}
	defer rows.Close()

	var result []podKey
	for rows.Next() {
		var ns, pod string
		if err := rows.Scan(&ns, &pod); err != nil {
			continue
		}
		result = append(result, podKey{Namespace: ns, Pod: pod})
	}
	return result
}

func exportPod(ctx context.Context, vz *pxapi.VizierClient, dsn string, pk podKey) {
	for _, table := range tables {
		script := makeExportScript(table, pk.Namespace, pk.Pod, dsn)
		if err := runPxL(ctx, vz, script); err != nil {
			log.Printf("  %s/%s %s: %v", pk.Namespace, pk.Pod, table, err)
		} else {
			log.Printf("  %s/%s %s: ok", pk.Namespace, pk.Pod, table)
		}
	}
}

func makeExportScript(table, namespace, pod, dsn string) string {
	return fmt.Sprintf(`
import px
df = px.DataFrame('%s', start_time='-%ds')
df = df[df.ctx['namespace'] == '%s']
df = df[df.ctx['pod'] == '%s']
df.hostname = px._pem_hostname()
df.event_time = px.now()
px.export(df, px.otel.ClickHouseRows(
    table='%s',
    endpoint=px.otel.Endpoint(url='%s'),
))
`, table, exportWindow, namespace, pod, table, dsn)
}

func runPxL(ctx context.Context, vz *pxapi.VizierClient, script string) error {
	rs, err := vz.ExecuteScript(ctx, script, noopMux{})
	if err != nil {
		return err
	}
	if err := rs.Stream(); err != nil {
		return err
	}
	return nil
}

// noopMux discards result tables — we only care about the export side effect
type noopMux struct{}
type noopHandler struct{}

func (noopMux) AcceptTable(ctx context.Context, metadata types.TableMetadata) (pxapi.TableRecordHandler, error) {
	return noopHandler{}, nil
}
func (noopHandler) HandleInit(ctx context.Context, metadata types.TableMetadata) error { return nil }
func (noopHandler) HandleRecord(ctx context.Context, record *types.Record) error       { return nil }
func (noopHandler) HandleDone(ctx context.Context) error                               { return nil }

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("required env var %s not set", key)
	}
	return v
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envOrInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		n, err := strconv.Atoi(v)
		if err == nil {
			return n
		}
	}
	return fallback
}
