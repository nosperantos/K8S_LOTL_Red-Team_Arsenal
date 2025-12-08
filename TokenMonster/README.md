# 𝗧𝗼𝗸𝗲𝗻𝗠𝗼𝗻𝘀𝘁𝗲𝗿 👾

> **WARNING:** 🕶️ For _authorized penetration testing_, purple/red/blue team ops, and cloud cluster maniacs only.

---

## 💣 Mission

**TokenMonster** is your bash-based RBAC sweeper, engineered for Kubernetes cluster mischief and defense.

No Python. No Go. No CLI flags. No arguments.  
Just shell & kubectl.  
Drop into almost any container and let the monster loose—autonomously seeks, scans, and devours all token and RBAC opportunities.

---

## 🔥 How Does It Work?

Run the script.  
Sit back.  
TokenMonster detects the environment, hunts for Kubernetes secrets, service account tokens, and RBAC configs automatically—no input needed.

- Finds available RBAC and service account tokens
- Scans local filesystem, in-cluster metadata, and default locations
- Reports what you (or your pod) can do in the cluster
- Zero configuration, zero interaction  
- All results dumped for your hacking or defending pleasure

---

## 🎯 Why TokenMonster?

- **Red Team**  
  💀 Auto-pillages service account tokens  
  🔓 Sees what the pod can really do via RBAC  
  👻 No arguments—no footprints—true LOTL stealth

- **Blue Team**  
  🔥 Audit RBAC from "ground zero": what would attackers see?  
  🚦 Hunt for excessive privileges and token sprawl  
  🧑‍🚒 Rapid-fire incident response: instant visibility

---

## ⚠️ Kubernetes RBAC: The Problem

RBAC *should* be tight. But...  
- YAML configs get gnarly  
- Legacy bindings linger  
- Namespace scoping gets lost  
- Default accounts have too much power  
- Pods leak tokens like a sieve

TokenMonster makes all this *painfully* obvious in seconds.

---

## 🚀 Quick Deploy

1. **Download or copy the script to any pod/container with `kubectl` access.**
    ```bash
    curl -O https://raw.githubusercontent.com/nosperantos/K8S_LOTL_Red-Team_Arsenal/main/TokenMonster/tokenmonster.sh
    chmod +x tokenmonster.sh
    ```

2. **Execute and unleash:**
    ```bash
    ./tokenmonster.sh
    ```

That’s it.  
No flags. No options. No questions asked.

---

## 🕵️ Results

- **Full dump** of service account tokens found
- **Mapped RBAC permissions** accessible to current context
- **Summary** of what actions (verbs/resources) are available
- **Suggestions** for escalation and privilege hunting

---

## 👀 Operator Tips

- Use *only* in authorized environments  
- Immediately rotate secrets after testing  
- Least privilege = best privilege  
- Monster always leaves footprints—watch your back

---

## 📚 References

- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Kubernetes Service Accounts](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/)
- [MITRE ATT&CK: Living off the land](https://attack.mitre.org/techniques/T1218/)

---

## 🏴‍☠️ License

For **EDUCATIONAL** and **AUTHORIZED** use only.  
TokenMonster cannot be caged.  
You release the monster at your own risk.

---
```
Hack the cluster. Defend the cluster. Monster no ask—monster just hunt.
```
