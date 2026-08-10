# <Customer> — AWS Landing Zone Accelerator Intake & Requirements

> **What this is.** Every input we need from you before we build your AWS Landing Zone.
> Most of these decisions are **irreversible after the first deployment**, so we collect
> them in writing rather than guessing.
>
> **How to fill it.** Type into the **Answer** column. Leave nothing blank — if something
> is unknown, write `TBD` and we will track it as an open item. Items marked
> 🔒 **IRREVERSIBLE** cannot be changed later without rebuilding the landing zone.
>
> **Return to:** <engineer name / email>  ·  **Target date:** <date>

| | |
|---|---|
| Customer | `<Customer>` |
| Prepared by | <engineer> |
| Version / date | v1 · <date> |
| Completed by (customer) |  |
| Date completed |  |

---

## 0. Who fills what

| Section | Owner on your side | Why we need it |
|---|---|---|
| 1 — Contacts & ownership | Project lead | Escalation + sign-off |
| 2 — Email distribution | IT / messaging admin | 🔒 Account root emails are permanent |
| 3 — Current AWS state | AWS account owner | Determines bootstrap path |
| 4 — Regions | Architecture / compliance | 🔒 Home region is fixed |
| 5 — Naming prefix | Architecture | 🔒 Fixed at first deploy |
| 6 — OU structure | Security / architecture | 🔒 OU names fixed at first deploy |
| 7 — Accounts | Architecture + IT | 🔒 Emails permanent |
| 8 — Networking / on-prem CIDRs | Network team | 🔒 VPC CIDRs are permanent |
| 9 — Identity / SSO | Identity team | Rework is disruptive |
| 10 — Config repository | DevOps | Needed before install |
| 11 — Compliance | Security / GRC | Drives guardrails |
| 12 — Tagging & cost | FinOps | Drives chargeback |
| 13 — Logging, encryption, backup | Security / ops | Drives retention cost |

---

## 1. Contacts & ownership

| # | Question | Answer |
|---|---|---|
| 1.1 | Project sponsor (name, title, email) |  |
| 1.2 | Technical lead / day-to-day contact (name, email, phone) |  |
| 1.3 | Network contact (for section 8) |  |
| 1.4 | Identity / IdP contact (for section 9) |  |
| 1.5 | Security / compliance contact (for section 11) |  |
| 1.6 | Billing / FinOps contact (for section 12) |  |
| 1.7 | Who signs off on this document? |  |
| 1.8 | Change-window / freeze periods we must avoid |  |

### Break-glass access

| # | Question | Answer |
|---|---|---|
| 1.9 | Who owns the **management account root credentials** today? |  |
| 1.10 | Is root MFA enabled on the management account? (yes/no — must be yes) |  |
| 1.11 | Named break-glass user #1 (person, not a shared inbox) |  |
| 1.12 | Named break-glass user #2 (backup) |  |
| 1.13 | Where are break-glass credentials stored? (vault / safe) |  |
| 1.14 | Who is notified when break-glass is used? |  |

---

## 2. Email distribution & notification addresses 🔒

> **Read this first.** Every AWS account needs a **globally unique** root email address —
> unique across *all of AWS*, not just your organization. Once an address is used for an
> account it can **never** be reused, even after the account is closed. These addresses
> receive password resets and AWS security notices, so they must be **monitored
> distribution lists**, never a personal mailbox belonging to one employee.

### 2.1 Management account (existing) — ask, do not derive

| # | Question | Answer |
|---|---|---|
| 2.1.1 | 🔒 **Exact existing root email of your AWS management (payer) account** |  |
| 2.1.2 | Who receives mail sent to it today? |  |
| 2.1.3 | Can you access that mailbox right now (for MFA / verification mails)? |  |

### 2.2 Alias pattern for the new accounts

All other accounts are created fresh, so they can use one base inbox with plus-addressing
(`aws-managers+log@yourdomain.com` all lands in `aws-managers@yourdomain.com`).

| # | Question | Answer |
|---|---|---|
| 2.2.1 | Base inbox we should use (e.g. `aws-managers@yourdomain.com`) |  |
| 2.2.2 | Is it a distribution list with ≥2 members? (yes/no) |  |
| 2.2.3 | **Plus-addressing test:** send mail to `<base>+test@yourdomain.com`. Did it arrive? (yes/no) |  |
| 2.2.4 | If **no** — you must supply a distinct real mailbox per account in 2.3 |  |
| 2.2.5 | Any mail filtering/quarantine that could drop AWS mail? (Mimecast, Proofpoint…) |  |

> ⚠️ Some mail systems silently discard the `+tag` part. If 2.2.3 fails, **every** account in
> section 7 needs its own real, distinct mailbox — please create them before we start.

### 2.3 Per-account root emails

Fill one row per account (mirror section 7). Use the plus-alias pattern if 2.2.3 passed.

| Account | Purpose | Root email |
|---|---|---|
| Management | Org owner / payer | *(from 2.1.1)* |
| LogArchive | Central log archive |  |
| Audit | Security tooling / delegated admin |  |
| Network | Transit gateway, inspection |  |
| SharedServices | Shared tooling |  |
| Perimeter | Ingress / egress / NAT |  |
| `<customer>`-prd | Production workloads |  |
| `<customer>`-dev | Development workloads |  |
| `<customer>`-tst | Test workloads |  |
| *(add rows as needed)* |  |  |

### 2.4 Operational notification addresses

These are *not* root emails — they are the distribution lists AWS sends alerts to. They can
repeat, and they should be team lists.

| # | Notification type | Address | Who acts on it |
|---|---|---|---|
| 2.4.1 | **Security alerts** (GuardDuty, Security Hub, IAM findings) |  |  |
| 2.4.2 | **Billing / cost anomalies + budget alerts** |  |  |
| 2.4.3 | **Operations / CloudWatch alarms** |  |  |
| 2.4.4 | **Pipeline / deployment failures** (LZA CodePipeline) |  |  |
| 2.4.5 | **AWS Health / service events** |  |  |
| 2.4.6 | AWS account **alternate contacts** — Billing |  |  |
| 2.4.7 | AWS account **alternate contacts** — Operations |  |  |
| 2.4.8 | AWS account **alternate contacts** — Security |  |  |

> 📬 **Action for you:** SNS subscriptions must be **confirmed by clicking a link in the
> email**. Whoever owns the mailboxes above must watch for AWS confirmation mails on
> deployment day, or alerts will never be delivered.

| # | Question | Answer |
|---|---|---|
| 2.4.9 | Who will confirm the SNS subscription emails on deployment day? |  |
| 2.4.10 | Should alerts also go to a ticketing system / Slack / Teams? Which, and how? |  |

---

## 3. Current AWS state

| # | Question | Answer |
|---|---|---|
| 3.1 | Do you already have an AWS Organization? (yes/no) |  |
| 3.2 | Management account ID |  |
| 3.3 | Is AWS Control Tower already deployed? (yes/no — if yes, which region + version) |  |
| 3.4 | Existing OUs and accounts (attach a list, or "none") |  |
| 3.5 | Existing accounts you want **brought into** the new org (ID + owner + purpose) |  |
| 3.6 | Any existing resources named `AWSAccelerator-*` in the management account? |  |
| 3.7 | Existing enterprise support / reseller / MSP relationship? |  |
| 3.8 | Existing third-party tooling that touches the org (CSPM, backup, SIEM)? |  |
| 3.9 | Is this management account brand-new, or does it run workloads today? |  |

---

## 4. Regions 🔒

| # | Question | Answer |
|---|---|---|
| 4.1 | 🔒 **Home region** (where the landing zone control plane lives) |  |
| 4.2 | Additional governed regions, if any |  |
| 4.3 | Data-residency rules that force a region (which law/policy?) |  |
| 4.4 | Is a DR region required at launch? Which? |  |
| 4.5 | Any opt-in regions needed (Cape Town, Bahrain, Jakarta, Hyderabad, Zurich, Hong Kong, UAE, Milan…)? |  |
| 4.6 | Regions that must be **explicitly blocked** for workloads |  |

> 💰 Each governed region carries a fixed baseline cost (Control Tower, Config, GuardDuty,
> Security Hub) before you run any workload. We recommend starting with one region.

---

## 5. Resource naming prefix 🔒

Every landing-zone-managed resource is named `<prefix>-…` (roles, keys, buckets, stacks, SCPs).

| # | Question | Answer |
|---|---|---|
| 5.1 | Use the default `AWSAccelerator`, or a custom lowercase prefix? |  |
| 5.2 | If custom — 🔒 exact string (lowercase, short, no spaces) |  |
| 5.3 | Any branding/naming standard this must follow? |  |
| 5.4 | Any tooling that expects a specific resource-naming convention? |  |

---

## 6. Organizational Unit structure 🔒

> **Proposed default** — please approve or mark changes:
>
> ```
> Root
> ├── Security            → LogArchive, Audit
> ├── Infrastructure      → Network, SharedServices, Perimeter
> ├── Workloads
> │   ├── Prod
> │   ├── Test
> │   ├── Dev
> │   └── Sandbox
> └── Suspended           → decommissioned accounts
> ```

| # | Question | Answer |
|---|---|---|
| 6.1 | Do you approve the proposed OU tree? (yes / changes below) |  |
| 6.2 | If changing — do you organize by **environment**, **business unit**, or **compliance scope**? |  |
| 6.3 | 🔒 Exact OU names you want (names cannot be changed after deployment) |  |
| 6.4 | Any workloads needing fundamentally different guardrails (e.g. PCI)? |  |
| 6.5 | Existing convention for suspended/decommissioned accounts? |  |

---

## 7. Account inventory 🔒

| # | Question | Answer |
|---|---|---|
| 7.1 | Do you approve the six baseline accounts (Management, LogArchive, Audit, Network, SharedServices, Perimeter)? |  |
| 7.2 | How many workload accounts at launch? |  |
| 7.3 | Naming convention for workload accounts (e.g. `<customer>-<app>-<env>`) |  |
| 7.4 | Do you need a dedicated sandbox account per team? |  |
| 7.5 | Expected account count at year 3 (drives address-space reservation) |  |

**Workload accounts to create at launch** (add rows as needed):

| Account name | OU | Owner / team | Purpose | Root email (see 2.3) |
|---|---|---|---|---|
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |

> ℹ️ AWS limits new-account creation to roughly **10 per hour**. If you need 15+ accounts on
> day one we will deploy in two passes.

---

## 8. Networking — on-prem CIDR confirmation 🔒

> **The single most important section.** VPC address ranges are permanent for the life of
> the VPC. If our proposed ranges overlap anything you can already reach — on-prem, VPN,
> Direct Connect, another cloud, a partner network — routing will silently break, and the
> only fix is renumbering. We need the **complete** list, including ranges that are merely
> *planned* or *reserved*.

### 8.1 Every reachable range we must avoid

List **all** of them. Add rows freely.

| # | CIDR (e.g. `10.10.0.0/16`) | Source (on-prem / VPN / DX / Azure / GCP / partner) | Site or description | In use today or planned? |
|---|---|---|---|---|
| 1 |  |  |  |  |
| 2 |  |  |  |  |
| 3 |  |  |  |  |
| 4 |  |  |  |  |
| 5 |  |  |  |  |
| 6 |  |  |  |  |
| 7 |  |  |  |  |
| 8 |  |  |  |  |

### 8.2 Confirmation ✍️

| # | Statement | Confirm (initials + date) |
|---|---|---|
| 8.2.1 | The table in 8.1 is the **complete** list of ranges reachable from AWS, including planned ones |  |
| 8.2.2 | Someone from the network team has reviewed it |  |
| 8.2.3 | We understand that a range omitted here may require rebuilding a VPC later |  |

### 8.3 Approve the proposed AWS address space

> **Proposed:** supernet `10.240.0.0/13` (covers `10.240.0.0`–`10.247.255.255`), split as:
> hub VPCs in `10.240.x`, and one `/16` per workload spoke — Prod `10.242.0.0/16`,
> Dev `10.243.0.0/16`, Test `10.244.0.0/16`, with `10.245+` reserved for growth.
> We deliberately use a **high 10-block** because most on-prem networks sit in `10.0`–`10.9`.

| # | Question | Answer |
|---|---|---|
| 8.3.1 | Does `10.240.0.0/13` conflict with anything in 8.1 or with future plans? |  |
| 8.3.2 | If it conflicts — is `172.16.0.0/12` free instead? Or propose a base |  |
| 8.3.3 | Do you approve the proposed layout? (yes / changes) |  |
| 8.3.4 | Any range you want **reserved** for future non-AWS use? |  |

### 8.4 Connectivity

| # | Question | Answer |
|---|---|---|
| 8.4.1 | How will AWS connect to on-prem? (Site-to-Site VPN / Direct Connect / both / none) |  |
| 8.4.2 | If DX — existing connection, location, bandwidth, and who owns it? |  |
| 8.4.3 | On-prem routers/firewalls terminating the tunnels (vendor + public IPs) |  |
| 8.4.4 | BGP ASN on your side (and any ASN we must avoid) |  |
| 8.4.5 | Bandwidth + latency expectations |  |
| 8.4.6 | Existing AWS VPCs that must connect to the new landing zone (IDs + CIDRs) |  |
| 8.4.7 | Other clouds to connect (Azure/GCP) — how? |  |

### 8.5 DNS

| # | Question | Answer |
|---|---|---|
| 8.5.1 | On-prem DNS domains AWS must resolve |  |
| 8.5.2 | On-prem DNS server IPs (for outbound forwarding) |  |
| 8.5.3 | Should on-prem resolve AWS private zones? (inbound resolver) |  |
| 8.5.4 | Public DNS provider + who manages it (Route 53? external registrar?) |  |
| 8.5.5 | Internal domain name to use in AWS (e.g. `aws.<customer>.internal`) |  |

### 8.6 Egress, inspection & ingress

| # | Question | Answer |
|---|---|---|
| 8.6.1 | Must all internet-bound traffic be **inspected** (firewall) or is NAT-only acceptable? |  |
| 8.6.2 | Must internet egress leave via **on-prem** instead of AWS? |  |
| 8.6.3 | Domain allow/deny list to enforce on egress (attach if long) |  |
| 8.6.4 | Public-facing workloads at launch? (drives ingress VPC + WAF) |  |
| 8.6.5 | Existing firewall vendor you want in AWS (Palo Alto, Fortinet…) or AWS Network Firewall? |  |
| 8.6.6 | Are IPv6 addresses required? (yes/no) |  |
| 8.6.7 | Number of Availability Zones per VPC (default 3) |  |

---

## 9. Identity & access (SSO)

| # | Question | Answer |
|---|---|---|
| 9.1 | Is AWS IAM Identity Center already enabled? (yes/no — if yes, which region, how many users) |  |
| 9.2 | Your primary identity provider (Entra ID / Okta / Google / Ping / on-prem AD / none) |  |
| 9.3 | Do you want AWS access federated from it? |  |
| 9.4 | Who administers the IdP (name + email)? |  |
| 9.5 | Existing permission sets / roles we must preserve |  |
| 9.6 | Groups that should map to AWS access (e.g. `AWS-Admins`, `AWS-Developers`) |  |
| 9.7 | Is MFA enforced at the IdP? |  |
| 9.8 | Any users needing CLI/programmatic access? |  |

**Permission sets to create** (add rows):

| Permission set | Who gets it | Which accounts/OUs | Access level |
|---|---|---|---|
| Administrator |  |  | Full |
| ReadOnly |  |  | View |
| Developer |  |  |  |
| Auditor |  |  |  |

---

## 10. Configuration repository

The landing zone config lives in Git and drives the deployment pipeline.

| # | Question | Answer |
|---|---|---|
| 10.1 | Git provider (GitHub / GitHub Enterprise / GitLab / Bitbucket) |  |
| 10.2 | Organization / workspace name |  |
| 10.3 | Repository name (new or existing?) |  |
| 10.4 | Branch to deploy from (e.g. `main`) |  |
| 10.5 | Who can approve merges to that branch? |  |
| 10.6 | Who has admin rights to authorize the AWS ↔ Git connection? |  |
| 10.7 | Is the repo private, and does it allow AWS connections (no IP allow-list blocking)? |  |
| 10.8 | Should we require PR review before deployment? (recommended: yes) |  |

---

## 11. Compliance & security scope

| # | Question | Answer |
|---|---|---|
| 11.1 | Compliance frameworks you must meet (PCI DSS, HIPAA, SOC 2, ISO 27001, NIST, GDPR…) |  |
| 11.2 | Which workloads/accounts are **in scope** for each? |  |
| 11.3 | Preferred CIS benchmark version (v1.4 / v3.0) |  |
| 11.4 | Do you have an existing security baseline/policy document? (attach) |  |
| 11.5 | Existing SIEM to forward logs to (Splunk, Sentinel, Datadog…)? |  |
| 11.6 | Required log retention period (years) |  |
| 11.7 | Services that must be **blocked** org-wide |  |
| 11.8 | Do you need a dedicated audit/read-only role for external auditors? |  |
| 11.9 | Vulnerability scanning expectations (Amazon Inspector? third party?) |  |
| 11.10 | Incident response contact + process |  |

---

## 12. Tagging & cost allocation

> **Proposed minimum taxonomy** — approve or amend:

| Tag key | Example value | Purpose |
|---|---|---|
| `<org>:env` | `prod`, `dev`, `test` | Environment |
| `<org>:owner-email` | `team@customer.com` | Contact |
| `<org>:cost-center` | `CC-1234` | Chargeback |
| `<org>:component` | `payments-api` | Application |
| `<org>:managed-by` | `lza`, `terraform` | Ownership of the resource |
| `BackupPlan` | `Daily`, `Weekly` | Selects the backup schedule |

| # | Question | Answer |
|---|---|---|
| 12.1 | Do you have an existing tag taxonomy? (attach — we'll use yours) |  |
| 12.2 | Tag key prefix to use (e.g. `acme:`) |  |
| 12.3 | Valid values for `cost-center` (or where we get the list) |  |
| 12.4 | Should tags be **advisory** (reported) or **enforced** (blocking) at launch? |  |
| 12.5 | Is cost chargeback a hard requirement, and by when? |  |
| 12.6 | Monthly budget threshold + who gets the alert |  |
| 12.7 | Do workload teams deploy via Terraform/CDK (tags must match there too)? |  |

---

## 13. Logging, encryption & backup

| # | Question | Answer |
|---|---|---|
| 13.1 | Log retention in the central archive (default 365 days + long-term Glacier) |  |
| 13.2 | Do you require customer-managed KMS keys with your own rotation policy? |  |
| 13.3 | Any requirement for an external key store (CloudHSM / XKS)? |  |
| 13.4 | Backup requirement per environment (RPO/RTO for prod, dev, test) |  |
| 13.5 | Backup retention + do you need cross-region or cross-account copies? |  |
| 13.6 | Existing backup tooling to keep (Veeam, Commvault, Rubrik…)? |  |
| 13.7 | Do you need object-lock / WORM on logs (regulatory)? |  |

---

## 14. Timeline & logistics

| # | Question | Answer |
|---|---|---|
| 14.1 | Target date for landing zone go-live |  |
| 14.2 | First workload to migrate + its date |  |
| 14.3 | Deployment window (deployments take several hours) |  |
| 14.4 | Who must be available on deployment day (mailbox owner, network, IdP admin)? |  |
| 14.5 | Existing AWS support plan (Business/Enterprise recommended) |  |
| 14.6 | Training/handover expectations for your team |  |

---

## 15. Attachments checklist

Please return these with the form:

- [ ] Current network diagram (on-prem + any existing cloud)
- [ ] Complete on-prem CIDR list (if longer than section 8.1)
- [ ] Existing AWS account inventory (if any)
- [ ] Existing tagging standard (if any)
- [ ] Security/compliance policy documents relevant to scope
- [ ] IdP group list for AWS access mapping

---

## 16. Sign-off

By signing, you confirm the answers above — in particular the **irreversible** items:
management account root email (2.1.1), home region (4.1), naming prefix (5.2), OU names
(6.3), account emails (2.3), and the on-prem CIDR list (8.1/8.2).

| Role | Name | Signature | Date |
|---|---|---|---|
| Customer technical lead |  |  |  |
| Customer security/compliance |  |  |  |
| Customer network lead |  |  |  |
| Delivery lead |  |  |  |

---

### For internal use — mapping to the plan

| Form section | Plan decision |
|---|---|
| 5 | Decision 1 — AcceleratorPrefix |
| 4 | Decision 2 — Region strategy |
| 6 | Decision 3 — OU structure |
| 2, 7 | Decision 4 — Account inventory |
| 8 | Decision 5 — CIDR / network plan |
| 9 | Decision 6 — IAM Identity Center |
| 11 | Decision 7 — Compliance scope |
| 12 | Decision 8 — Tagging |
| 1, 3, 10, 13, 14 | Bootstrap prerequisites (`/lza-bootstrap`) |
