#!/bin/bash
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
          echo "    ═══════════════════════════════════════════════════════"
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
  kubectl get clusterrolebinding -o json | jq -r '.items[] | select(.subjects[]? | select(.kind == "ServiceAccount")) | "\(.metadata.name)|\(.roleRef.name)|\(.subjects[] | select(.kind == "ServiceAccount") | "\(.namespace):\(.name)")"' | while IFS='|' read -r binding role subject
  do
    echo "  $subject -> ClusterRole: $role via ClusterRoleBinding: $binding"
  done
  
  echo ""
done
