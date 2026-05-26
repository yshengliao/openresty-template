# Kubernetes 部署參考

本文件說明將 OpenResty Gateway 部署至 Kubernetes 時的環境變數與設定參考。

---

## 環境變數

完整環境變數清單請見 [README.md → Configuration](../README.md#configuration)（`SERVICE_NAME`、`BUILD_COMMIT_TAG`、`BUILD_COMMIT_SHA`、`JaegerCollector_Host`、`JaegerCollector_OTLPHttpPort`）。

### K8s 注入方式

K8s Deployment 透過 `env` 或 `envFrom` 注入，下方「Deployment 範例」可直接複製。

### 自定義環境變數

K8s 與 Docker 共通流程，需三步：

1. 在 `script/script.env.conf` 加入宣告：
   ```nginx
   env YOUR_NEW_VAR;
   ```
2. 在 `script/config.lua` 的 `_M.ENV` table 讀取：
   ```lua
   YOUR_NEW_VAR = os.getenv("YOUR_NEW_VAR") or "default_value",
   ```
3. 在 Lua 端點中使用：
   ```lua
   local config = require("config")
   local value  = config.ENV.YOUR_NEW_VAR
   ```

> OpenResty/Nginx 不會自動將容器環境變數傳入 Lua runtime，必須在 `script.env.conf` 以 `env VAR_NAME;` 明確宣告。

---

## Deployment 範例

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  labels:
    app: api-gateway
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      containers:
        - name: gateway
          image: your-registry.com/api-gateway:v1.0.0
          ports:
            - containerPort: 8080
              protocol: TCP
          env:
            - name: BUILD_COMMIT_TAG
              value: "v1.0.0"
            - name: BUILD_COMMIT_SHA
              value: "abc1234567890"
          envFrom:
            - configMapRef:
                name: gateway-config
          livenessProbe:
            httpGet:
              path: /healthcheck
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ping
              port: 8080
            initialDelaySeconds: 3
            periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
```

---

## Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
spec:
  selector:
    app: api-gateway
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: ClusterIP
```

---

## ConfigMap

將非敏感的環境變數放在 ConfigMap：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gateway-config
data:
  JaegerCollector_Host: "jaeger-collector.observability.svc.cluster.local"
  JaegerCollector_OTLPHttpPort: "4318"
```

---

## Secret

敏感資訊（API keys、JWT secrets 等）使用 Secret：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gateway-secrets
type: Opaque
stringData:
  JWT_SECRET: "your-secret-here"
```

在 Deployment 引用：

```yaml
envFrom:
  - secretRef:
      name: gateway-secrets
```

並記得在 `script/script.env.conf` 加入 `env JWT_SECRET;`。

---

## 健康檢查 → K8s Probe 對應

端點本身的行為（回應內容、access log 關閉等）見 [README.md → Health Check](../README.md#health-check)。
K8s 建議對應：

| 端點 | K8s probe |
|---|---|
| `/healthcheck` | `livenessProbe` — 確認程序存活 |
| `/ping` | `readinessProbe` — 確認可接收流量 |

---

## 多實例部署注意事項

- **Lua code cache**：生產環境務必保持 `lua_code_cache on`（預設值），否則每次請求都會重新載入 Lua 檔案。
- **worker_processes**：Dockerfile 中預設為 `auto`，在 K8s 中會偵測 Pod 的 CPU limit。如需手動控制，可在 `nginx.conf` 指定。
- **lua_shared_dict**：跨 worker 的共用記憶體，在 K8s 環境中僅限單一 Pod 內共用，不跨 Pod。如需跨 Pod 共用狀態，應使用外部儲存（Redis 等）。
- **DNS resolver**：預設為 `127.0.0.11`（Docker 內建 DNS，適用一般 Docker 網路）。K8s 叢集內需改為 CoreDNS；複製 `conf/local/nginx.http.resolver.inc.sample` 並命名為 `conf/local/nginx.http.resolver.inc`，調整內容：
  ```nginx
  # conf/local/nginx.http.resolver.inc
  resolver  kube-dns.kube-system.svc.cluster.local  valid=30s ipv6=off;
  # 或直接指定 CoreDNS cluster IP（通常為 10.96.0.10）：
  # resolver  10.96.0.10  valid=30s ipv6=off;
  ```
  此檔案已在 `.gitignore` 中排除，各環境個別設定，不進版本控制。

---

## 映像構建

建議在 CI/CD pipeline 中注入版本資訊：

```bash
docker build \
  --build-arg BUILD_COMMIT_TAG=$(git describe --tags --always) \
  --build-arg BUILD_COMMIT_SHA=$(git rev-parse HEAD) \
  -t your-registry.com/api-gateway:$(git describe --tags --always) \
  .
```

> 目前 Dockerfile 尚未使用 `ARG` 接收這些值，環境變數由 K8s env 注入即可。如需 bake 進 image，可在 Dockerfile 加入 `ARG` 和 `ENV` 指令。
