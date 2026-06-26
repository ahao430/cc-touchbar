# 04 - cc switch 桥接层（SQLite 只读）

> 仅当 `activeSource == .ccSwitch` 时启用。详见 [03-数据源策略.md](03-数据源策略.md)。
>
> cc switch 是 Tauri GUI 应用，**没有 CLI**。所有读取通过它的 SQLite db 直接完成。
>
> **写操作一律走 GUI 唤起**，不直写 db —— Tauri 进程持有内存状态，直改 SQLite 不会触发它 reload，也不会让它重写 `~/.claude/settings.json`。

## 为什么是 SQLite

最初假设 cc switch 有 CLI（`cc switch status --json`），实测发现：
- `/Applications/CC Switch.app/Contents/MacOS/cc-switch` 是 Tauri GUI binary
- 不接受 `--help` / `status --json` 等子命令
- 所有运行时状态都在 `cc-switch.db` 里
- 还有一个本地代理 `127.0.0.1:15721`，但那是给 Claude Code 的请求路径，不是管理 API

## 关键表 schema

| 表 | 用途 | 关键字段 |
|---|---|---|
| `providers` | provider 注册表，按 `app_type` 分组 | `id`、`app_type`、`name`、`is_current`、`provider_type`、`limit_daily_usd`、`limit_monthly_usd`、`cost_multiplier` |
| `provider_endpoints` | 每 provider 的 endpoint URL | `provider_id`、`app_type`、`url` |
| `provider_health` | 健康 + 熔断状态 | `is_healthy`、`consecutive_failures`、`last_error` |
| `proxy_config` | 本地代理配置 | `listen_port`（15721）、`auto_failover_enabled`、`circuit_*` 熔断阈值 |
| `proxy_request_logs` | 每次请求明细 | `request_id`、`provider_id`、`model`、tokens、cost、latency |
| `usage_daily_rollups` | **按天聚合用量** | `date`、`app_type`、`provider_id`、`model`、`total_cost_usd`、各 token 字段 |
| `model_pricing` | 模型定价表 | per-model 单价 |
| `settings` | key/value | `common_config_claude`、`claude_desktop_gateway_token` 等 |

完整 schema 可通过 `sqlite3 cc-switch.db ".schema"` 拿到。

## 路径解析

详见 [02-环境探测.md](02-环境探测.md)。**核心**：必须读 `~/Library/Application Support/com.ccswitch.desktop/app_paths.json` 拿 override，不能假定 `~/.cc-switch/`。

## 接口契约

### 只读

```swift
protocol CCSwitchReading {
    func activeProvider(appType: String = "claude") throws -> ProviderRow?
    func providers(appType: String = "claude") throws -> [ProviderRow]
    func costToday(appType: String = "claude") throws -> Double
    func costMonth(appType: String = "claude") throws -> Double
    func requestCountToday(appType: String = "claude") throws -> Int
    func proxyConfig(appType: String = "claude") throws -> ProxyConfigRow
    func providerHealth(providerId: String, appType: String = "claude") throws -> HealthRow?
    func costTodayByProvider(appType: String = "claude") throws -> [(ProviderRow, Double)]
}
```

### 写（保守策略）

```swift
protocol CCSwitchWriting {
    func openUI()
    func openUI(toProvider providerId: String) throws    // v3，需要 reverse-engineer deeplink
}
```

**为什么不直接改 SQLite 切 provider？**
- cc switch 是 Tauri 应用，运行中可能持有内存中的状态
- 直接改 `is_current` 不会触发它 reload，也不会自动改写 `~/.claude/settings.json`
- 风险高于收益。v1/v2 阶段一律走 GUI。

> v3 可探索：写 db 后 kill + relaunch cc-switch，或调它的 localhost API（如果有）。

## 关键查询

### 当前激活 provider

```sql
SELECT id, name, provider_type, limit_daily_usd, limit_monthly_usd, cost_multiplier
FROM providers
WHERE app_type = 'claude' AND is_current = 1
LIMIT 1;
```

### 所有 providers（含健康）

```sql
SELECT p.id, p.name, p.provider_type, p.is_current,
       p.limit_daily_usd, p.limit_monthly_usd, p.cost_multiplier,
       h.is_healthy, h.consecutive_failures, h.last_error
FROM providers p
LEFT JOIN provider_health h
  ON h.provider_id = p.id AND h.app_type = p.app_type
WHERE p.app_type = 'claude'
ORDER BY p.sort_index, p.name;
```

### 今日 cost

```sql
SELECT CAST(SUM(total_cost_usd) AS REAL) AS cost
FROM usage_daily_rollups
WHERE app_type = 'claude' AND date = date('now', 'localtime');
```

**注意：** `total_cost_usd` 在 schema 里是 TEXT，必须 `CAST AS REAL`。

### 本月 cost

```sql
SELECT CAST(SUM(total_cost_usd) AS REAL)
FROM usage_daily_rollups
WHERE app_type = 'claude'
  AND date >= strftime('%Y-%m-01', 'now', 'localtime');
```

### 今日请求数

```sql
SELECT SUM(request_count)
FROM usage_daily_rollups
WHERE app_type = 'claude' AND date = date('now', 'localtime');
```

### 今日按 provider 分组

```sql
SELECT u.provider_id,
       p.name,
       CAST(SUM(u.total_cost_usd) AS REAL) AS cost,
       SUM(u.request_count) AS reqs
FROM usage_daily_rollups u
LEFT JOIN providers p ON p.id = u.provider_id AND p.app_type = u.app_type
WHERE u.app_type = 'claude' AND u.date = date('now', 'localtime')
GROUP BY u.provider_id
ORDER BY cost DESC;
```

### Proxy 配置

```sql
SELECT listen_address, listen_port, auto_failover_enabled,
       circuit_failure_threshold, circuit_timeout_seconds, enabled
FROM proxy_config
WHERE app_type = 'claude';
```

## DTO

```swift
struct ProviderRow: Codable, Equatable {
    let id: String
    let appType: String
    let name: String
    let isCurrent: Int
    let providerType: String?
    let limitDailyUSD: String?
    let limitMonthlyUSD: String?
    let costMultiplier: String?
    let isHealthy: Int?
    let consecutiveFailures: Int?
    let lastError: String?
}

struct UsageRollupRow: Codable {
    let date: String
    let providerId: String
    let model: String
    let totalCostUSD: String
    let requestCount: Int
    let inputTokens: Int
    let outputTokens: Int
}

struct ProxyConfigRow: Codable {
    let listenAddress: String
    let listenPort: Int
    let autoFailoverEnabled: Int
    let enabled: Int
}

struct HealthRow: Codable {
    let isHealthy: Int
    let consecutiveFailures: Int
    let lastError: String?
    let lastSuccessAt: String?
    let lastFailureAt: String?
}
```

## SQLite 访问注意事项

### 打开方式

```swift
static func open(_ url: URL, readonly: Bool) throws -> CCSwitchDB {
    var db: OpaquePointer?
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_WAL
    guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
        throw DBError.openFailed(sqlite3_errmsg(db))
    }
    return CCSwitchDB(handle: db)
}
```

### WAL 兼容

cc switch 几乎肯定用 WAL 模式（Tauri 默认）：
- 只读连接 + WAL = 不阻塞写者
- 但要确保 cc switch 的 WAL 文件（`cc-switch.db-wal`、`cc-switch.db-shm`）也在同目录可读
- 不要尝试 `PRAGMA wal_checkpoint`，那是写操作

### 缓存

- 内存缓存每个查询结果 2 秒
- FSEvents 监听 `.db` 文件 mtime，变化时立即失效全部缓存
- WAL 模式下 mtime 不一定每次写都变，TTL 是兜底

### 不可写

- 任何修改 db 的需求都要走 Bridge 显式接口并 review
- v3 评估"写 db + 让 cc switch reload"的可行性后再开

## 错误处理

| 错误 | 处理 |
|---|---|
| `sqlite3_open_v2` 失败 | 抛 `DBError.openFailed`，Setup 重新检测 |
| 表不存在 | 抛 `DBError.schemaMismatch`，提示用户升级 cc-switch |
| 查询失败 | 写 `AppState.lastError`，HUD 对应字段显示 `—` |
| 查询返回 NULL | DTO 字段用可选 / 默认值，不崩 |

## 性能预算

- 单次查询 < 10 ms（SQLite 本地文件）
- 完整刷新（5 个查询）< 50 ms
- 5 秒轮询对 cc switch 主进程零影响（只读 WAL）
