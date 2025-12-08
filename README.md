# K8S_LOTL_Red-Team_Arsenal

> 🩸 Useful tools for Red Teams operating "Living Off The Land" in Kubernetes & cloud-native environments  
> _blend, evade, enumerate – like a real adversary._  

---

## 🕵️ What Is "Living Off the Land" (LOTL)?

_LOTL_ is the art of using what's **already there**.  
Red Teamers and advanced adversaries avoid custom malware and instead weaponize **native binaries, built-in features, and misconfiguration**.  
It's stealthy. It’s noisy only if you know what to look for.

**Kubernetes is loaded with tools for attackers who know where to dig.**  
Why upload your own backdoor when you can pivot, persist, and escalate with `kubectl`, ServiceAccounts, or forgotten RBAC rules?

---

## 🚩 Why Cloud-Native LOTL and This Arsenal?

*These tools help you:*

- **Slip inside—and blend in:** No signatures, no binaries, just platform features abused cleverly.
- **Map the target:** Discover endpoints, secrets, and misconfigs others miss.
- **Go deep:** Attack paths, privilege escalation, stealth pivoting—all using the defender’s own toys.
- **Train and test:** Give Blue Teams a dose of reality with simulated TTPs that real attackers employ.

**If your team can defend _against these_, you’re doing well.**

---

## 🧨 Toolset:  
_Your weapons — use responsibly!_

### ── KubeFuzzer ──
**Purpose:**  
Fuzz Kubernetes API endpoints using custom dictionaries. Find hidden, legacy, or misconfigured resources lurking in the cluster.

**Why use:**  
- Reveal the real attack surface
- Test RBAC with adversary eyes
- Find stealthy footholds for persistence

**Run:**  
```sh
./kubefuzzer <file-with-relative-endpoint-urls>
```

---

### ── TokenMonster ──
**Purpose:**  
Rip through pods, containers, and volumes to discover ServiceAccount tokens and secrets. Validate access, check for privilege escalation goldmines.

**Why use:**  
- Spot leaked or overpowered tokens  
- Analyze what a compromised pod could do  
- Hit the API with the tokens you find

**Run:**  
```sh
bash token_monster.sh
```

---

## 🧬 More Coming Soon...

---

## 📝 References

- [Kubernetes Docs](https://kubernetes.io/docs/)
- [OWASP K8S Top 10](https://owasp.org/www-project-kubernetes-top-10/)

---

## ⚠️ Ethics

> These tools are for testing your own environments or with explicit permission ONLY.  
> Red Team with respect – don’t be a real threat actor.

---

*Own your ops. Know your risks. Blend in – then break out.*
