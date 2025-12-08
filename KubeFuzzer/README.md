# KubeFuzzer

> _Fuzz the unknown. Pwn the cluster. ✨_

A no-nonsense Kubernetes API endpoint fuzzer for operators who want to break things and ask questions later.

---

## What is KubeFuzzer?

KubeFuzzer rapidly probes Kubernetes API servers using customizable endpoint wordlists. If you're doing Red Team ops, pentesting, or just living that sysadmin villain arc, this tool boosts your API discovery game.

---

## Usage

**Basic scan:**
```bash
./kubefuzzer <dict.txt>
```

Example `dict.txt` entries:
```
api/v1/nodes
api/v1/secrets
apis/apps/v1/deployments
apis/rbac.authorization.k8s.io/v1/roles
...
```

**Pro Tips & Tricks for Real Operators**:

- 🏴‍☠️ _Wordlists are your weapon._ Start with endpoints from the [official docs](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.29/) and spice it up with weird or legacy endpoints (`v1beta1`, custom resources).
- ⛓️ _Chain your requests._ A 200 or 403 response can be just as valuable—follow up with privilege escalation or abuse overlooked endpoints.
- 🦇 _Hunt for secrets._ Fuzz paths like `api/v1/namespaces/<ns>/secrets` and wildcard namespaces. Many clusters expose juicy stuff here!
- 🕵️ _Enumerate CRDs._ Hit `/apis` then add discovered groups to your wordlist—attack what admins forget.
- 👀 _Check error codes._ Non-standard errors (500, 405, etc) can hint at internal components or misconfigured RBAC.
- 🏎️ _Speed kills._ Hammer endpoints for timing attacks—slower responses sometimes leak permissions or backend structure.
- 🎭 _Use stolen/kidnapped/kubeconfig tokens._ With valid Bearer creds, run KubeFuzzer using those for extra loot.

---

## 🚨 Example Red Team Flow

1. Extract kubeconfig/token from compromised container.
2. Build a custom wordlist from multiple sources (_docs, open repos, your own knowledge_).
3. Run KubeFuzzer and record all endpoints and their responses.
4. Map errors and successes, look for privilege escalation and juicy secrets.
5. Pivot! Use discovered paths for kubectl abuse, custom API calls, or even SSRF via misconfigured proxies.

---

## 📚 References

- [Kubernetes API Concepts](https://kubernetes.io/docs/concepts/overview/kubernetes-api/)
- [Common Kubernetes Attack Paths](https://attack.mitre.org/techniques/T1552/)

---

## ⚠️ Legal & Ethics

This tool is for authorized security testing and research _only_. Get permission before fuzzing; you are responsible for your own opsec.

---

_The cluster has secrets. Go find them._
