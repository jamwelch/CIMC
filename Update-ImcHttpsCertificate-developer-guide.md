# Update-ImcHttpsCertificate.ps1 — developer guide

This document walks the script **in source order** for someone who already *runs* PowerShell (`Get-Help`, pipelines, `-File`) but has not written many advanced `.ps1` files. It explains *why* each Project pattern is there. It is not an operator runbook: how to install `pwsh`, click through VDI, or copy-paste inventory commands lives in `Update-ImcHttpsCertificate-README.md`.

James copies this file into `Compute_Powershell_Scripts` next to the script. Agents do not clone or push that repo.

Line numbers refer to `Update-ImcHttpsCertificate.ps1` as generated (about 1361 lines). Treat them as approximate if the file is later edited. Function names are the stable anchors.

**No secrets.** This guide never includes passwords, PEM blocks, or private-key bytes. The `.ps1` must stay the same: treat it as public Git.

---

## Map of the file

| Lines (approx.) | What you are looking at |
| --- | --- |
| 1 | `#Requires` — engine gate |
| 2–40 | Banner comments — human-readable contract |
| 42–233 | Comment-based help — `Get-Help` |
| 235–344 | `[CmdletBinding]` + `param()` — the script’s public API |
| 346–394 | Strict mode, disclaimer, version check, instruct-only module import |
| 396–1242 | Helper functions (defined, not yet called) |
| 1244–1361 | Main — report, credential, CSV loop, export |

PowerShell runs a `.ps1` **top to bottom**. `#Requires` and `param()` are special (parsed before the body). Function *definitions* register when execution reaches them. The **main** block at the bottom is the actual run: it calls those functions. That split is deliberate: keep reusable logic named and testable, keep the entry point in one place.

---

## 1. `#Requires -Version 7.4` (line 1)

```powershell
#Requires -Version 7.4
```

`#Requires` is not a comment. The engine reads it **before** the script body. If the host is older than 7.4, PowerShell refuses to run the file.

**Why it exists.** The Project standard (`powershell-script-standard.md`) sets one floor for every emitted script: **PowerShell 7.4**. UCS PowerTool (`Cisco.IMC`) documents 5.1 / 6+, but `Intersight.PowerShell` documents **7.4.0**. One floor means coworkers never guess which host to use. Operators must launch **`pwsh`**, not Windows PowerShell 5.1 (`powershell.exe` / ISE).

There is a *second* version check later (lines 360–373) that prints upgrade **links** and then `return`s. `#Requires` is the hard gate (short engine error). The runtime block is the standard’s instruct-only message if the body still runs (for example the directive is removed, or someone pastes the body into a session). Neither path upgrades PowerShell. Never call `winget` or an installer from the script.

---

## 2. File banner (lines 2–40)

The `# =====` block is **not** `Get-Help`. It is what a human sees in Git or an editor before scrolling. The standard requires: generator (AI), human-tested / not production-certified, PS 7.4 floor, module list, “this script does not install or upgrade,” operator-only upgrade links, and a secrets policy.

Script-specific facts that belong in the banner (so they are not lost if help is skipped):

- **Modules:** `Cisco.IMC` only. `Cisco.UCS.Common` arrives as a Gallery dependency. Do not `Import-Module` unused UCS/Intersight modules.
- **Secrets:** prompt with `Get-Credential`; `PSCredential` in memory for this run; reuse for every CSV host; never `ConvertTo-SecureString -AsPlainText`; certs/keys are **paths**, not pasted PEM.
- **CIMC floor:** customer fleet 4.0.4+. Path A (CSR) on 4.0.4–4.1.1. Path B (external cert+key) only on 4.1.2+. Below 4.0.4 stops unless `-ContinueOnOldFirmware`. Path B is always refused below 4.1.2.
- **Cmdlet names** were taken from Cisco.IMC **3.0.6.23 MAML**, not from the 3.x examples chapter. Gallery 3.0.6.23 has **no** `Set-ImcCertificateManagement`; Path B activate is `Set-ImcManagedObject` with `AdminAction = activate-external-cert`.

Inline comments later in the file are reserved for non-obvious UCS/IMC behavior (session drop, `-Pwd` as a string, firmware parse). Do not narrate every pipeline step, and never leave a commented-out password “example.”

---

## 3. Comment-based help (lines 42–233)

The `<# ... #>` block uses Microsoft keywords (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES`, `.LINK`) so this works:

```powershell
Get-Help .\Update-ImcHttpsCertificate.ps1 -Full
```

**Why this placement.** For a script, comment-based help must sit at the top **or** immediately above `param()`. Here it sits after the banner and immediately before `[CmdletBinding]` / `param()`. That is the binding `Get-Help` looks for. If you move it below `param()` or into a random function, script-level help breaks.

**Why every `.PARAMETER` exists.** The standard requires a `.PARAMETER` entry for **every** `param()` name. Operators (and future you) should not have to open the `param()` block to learn `-CountryCode` is a full country name, not `US`.

`.DESCRIPTION` repeats the AI / human-test / must-test-before-production disclaimer. `.NOTES` repeats the 7.4 floor and “script never installs modules.” `.EXAMPLE` uses RFC documentation addresses only — never real keys.

This help is the **developer contract** for the public API. The operator README restates the same facts as a runbook. Do not fork them: if you add a parameter, add `.PARAMETER` here and a `param()` entry in the same change.

---

## 4. `[CmdletBinding]` and `param()` (lines 235–344)

```powershell
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param( ... )
```

These two must be **adjacent**. `[CmdletBinding()]` turns the file into an *advanced script*: common parameters (`-Verbose`, `-ErrorAction`, `-WhatIf`, `-Confirm`) appear automatically, and `$PSCmdlet` is available.

### Why `SupportsShouldProcess`

Destructive IMC work (CSR generate, cert upload, Path B activate) must honor `-WhatIf` / `-Confirm`. `SupportsShouldProcess = $true` wires those switches. The actual gate is `$PSCmdlet.ShouldProcess(...)` inside the Path A/B functions (see §9). If that call returns `$false` (`-WhatIf`, or the user said No to `-Confirm`), the function returns a `WhatIf: ...` string and does not call Cisco cmdlets that change the certificate.

`ConfirmImpact = 'Medium'` means a normal session (`$ConfirmPreference` defaults to `High`) does **not** prompt on every host. Operators can still pass `-Confirm` or `-WhatIf`. `High` would interrupt a 50-row CSV with a prompt per upload.

### Why this `param()` shape

| Pattern | Example | Why |
| --- | --- | --- |
| Typed, not Mandatory | `[string]$ImcAddress` | Either `-ImcAddress` or `-CsvPath` is required; that rule is enforced in `Get-ImcTargetList`, not with two Mandatory parameters (which would force both). |
| `PSCredential` | `$Credential`, `$RemoteShareCredential` | Password stays in a `SecureString` inside the object. Never a `[string]$Password`. |
| `ValidateSet` | `$Method`, `$SignatureAlgorithm`, `$RemoteProtocol` | Fail at bind time with a clear error, before any IMC login. Remote protocols are **scp/sftp only** (Cisco is deprecating TFTP/FTP/HTTP; private keys must not use them). |
| `ValidateRange` | `$ReconnectWaitSeconds` 15–600 | Prevents `0` (no wait after HTTPS drop) and absurd sleeps. |
| `[switch]` | `$ContinueOnOldFirmware`, `$SkipCertificatePreflight` | Boolean flags; presence means `$true`. |
| `[string[]]` | `$SubjectAlternativeName` | Multiple SAN entries (`DNS:...`, `IP:...`). |
| Defaults | `$Method = 'Inventory'`, `$SignatureAlgorithm = 'sha384'`, `$RemoteProtocol = 'scp'` | Safest first run is read-only inventory. sha384 matches current IMC GUI default. |

`sha1` / `md5` are **not** in `ValidateSet`. A later main-block check still refuses them if someone bypasses the set. That matches the Project crypto rule: do not generate SHA-1/MD5 signatures.

There are **no** hardcoded credentials, API keys, or `-----BEGIN` blocks in `param()` defaults. Certificate and key parameters are **paths**.

---

## 5. Runtime prelude (lines 346–394)

### Strict mode and error preference (346–351)

```powershell
Set-StrictMode -Version Latest
$stopOnError = ($ErrorActionPreference -eq 'Stop')
$ErrorActionPreference = 'Continue'
$InformationPreference = 'Continue'
```

- **`Set-StrictMode -Version Latest`** — using an uninitialized variable or an invalid property throws instead of silently becoming `$null`. That is how you catch typos in a 1300-line script.
- **`$stopOnError`** — capture whether the operator passed `-ErrorAction Stop` *before* overwriting preference. The CSV loop (main) continues after a failed host **unless** that flag was set. Advanced scripts receive `-ErrorAction` as a common parameter; reading `$ErrorActionPreference` here is how the script honors it after forcing `Continue` for the fleet loop.
- **`Continue`** — one bad CIMC must not abort the remaining rows by default (Project fleet preference).
- **`$InformationPreference = 'Continue'`** — `Write-Information` (used by `Write-ImcOpLog`) actually prints. The default is `SilentlyContinue`, which would hide the log-style lines.

### Disclaimer `Write-Warning` (353–358)

The standard requires the AI / human-test / non-production warning **at runtime**, not only in comments. Operators who never run `Get-Help` still see it. The script also states it will not install PowerShell or Gallery modules.

### Version check (360–373)

If `$PSVersionTable.PSVersion -lt [version]'7.4'`, `Write-Error` prints Microsoft install links (Windows / Linux / macOS) and `winget` as **text**, then `return`. The script never executes those installers.

### Instruct-only module check (375–394)

`$requiredModules = @('Cisco.IMC')`. `Get-Module -ListAvailable` looks on disk (installed), not only in the current session. If missing: print `Install-Module -Name Cisco.IMC -Scope CurrentUser` and Gallery URL, then `return`. **Do not** call `Install-Module` / `Update-Module` from the script unless James later asks for an explicit opt-in switch.

`Import-Module Cisco.IMC -ErrorAction Stop` runs only after the check. Import only what the body calls.

---

## 6. Helper functions — logging, CSV, firmware (lines 396–575)

Helpers are grouped before main so the bottom of the file reads as a short playbook. Names use an `Imc` prefix to avoid colliding with `Cisco.IMC` cmdlets (`Connect-Imc` vs `Connect-ImcTarget`).

### `Get-ImcRedactedText` (400–408)

Strips PEM private-key blocks, PEM certificate blocks, and `pwd=` / `password=` values from a string before it is logged. **Why:** exception messages and PowerTool errors can echo secrets. Every log/report path should pass text through this (or never receive PEM in the first place).

### `Write-ImcOpLog` (410–426)

One line: ISO-8601 timestamp, level (`INFO`/`WARN`/`ERROR`/`SKIP`), redacted message. Appends to the sidecar `.log` when `$LogPath` is set, and mirrors to `Write-Warning` / `Write-Error` / `Write-Information`. The log is **append-as-you-go**; the report CSV is written once at the end. If the process is killed mid-CSV, the `.log` is the surviving audit trail.

### `Test-ImcHostIdentity` (428–437)

Accepts IPv4/IPv6 (`IPAddress.TryParse`) or a conservative hostname/FQDN regex. Rejects schemes, paths, backslashes, and spaces. Used so a CSV cell like `https://imc/login` is skipped rather than passed to `Connect-Imc`.

### `Get-ImcCsvProperty` (439–455)

Case-insensitive lookup of the first non-empty column among several header aliases (`ImcAddress` / `IP` / `Host` / …). CSV authors do not have to match one exact header. Returns trimmed string or `$null`.

### `ConvertFrom-ImcFirmwareString` (457–471)

IMC versions look like `4.1(2c)` or `4.1.2`. This parses to `[version]` so you can compare to `4.0.4` and `4.1.2`. Unparseable strings return `$null`; callers **refuse to guess** Path B (see `Get-ImcControllerFirmwareInfo`).

### `Get-ImcReportPathPair` (473–488)

Default report: `Update-ImcHttpsCertificate-yyyyMMdd-HHmmss.csv` in the current directory. `-ReportPath` is resolved to an absolute path; missing directories are created. Sidecar log = same base name with `.log`. Returns a small object `{ CsvPath, LogPath }`.

### `Get-ImcTargetList` (490–575)

Builds the list of hosts **before** any login.

- If `-CsvPath` is set: CSV **wins**; `-ImcAddress` is ignored with a warning (documented operator rule).
- `Import-Csv` each row; empty or invalid addresses become target objects with `SkipReason` (still reported, not thrown).
- If no CSV: require a valid `-ImcAddress`; one synthetic target with `Source = 'param'`.
- Per-row `CertificatePath` / `PrivateKeyPath` / `ExpectedName` are stored on the target so the host function can override script parameters.

Returning skip-rows as objects (instead of dropping them) is why the report can show `Skipped` with a reason and still continue.

---

## 7. Certificate and key file checks (lines 577–742)

These run on the **workstation** against operator-supplied **paths**. They never print PEM. They exist because installing an expired, weak, or mismatched certificate can take IMC HTTPS down until serial recovery.

Unverified certificates loaded from disk can be expired, weakly keyed, SHA-1/MD5-signed, or self-signed. This script’s preflight is the gate; `-SkipCertificatePreflight` turns that gate off and is logged as a warning.

### `Test-ImcPrivateKeyFile` (577–603)

- File must exist; `.p12`/`.pfx` refused (not a CIMC upload format; script does not convert).
- On Linux/macOS, world-readable keys throw (`chmod 600` guidance; bytes not printed).
- First line must look like a PEM private-key header; `ENCRYPTED` keys are refused (IMC paste/upload does not document encrypted keys).

Header-only check: the function does not dump the key.

### `Test-ImcCertificatePreflight` (605–700)

Requires `openssl` on `PATH`. Runs `openssl x509 -text -noout -in <path>` and parses **text metadata** (not the PEM). Refuses:

| Check | Action |
| --- | --- |
| Expired (`Not After` in the past) | throw |
| Not yet valid | warning (IMC NTP/clock) |
| Signature MD5 or SHA-1 | throw |
| RSA < 2048 bits | throw |
| EC curves weaker than P-256 (P-192, P-224, secp192r1, …) | throw |
| Self-signed (Issuer == Subject) | warning — OK for lab, not for public-facing prod |
| CN/SAN vs `-ExpectedName` (including `*.example.com`) | throw if missing |
| Multiple `BEGIN CERTIFICATE` blocks | warning — CIMC HTTPS docs show a single server cert |

Returns a small summary object (CN, issuer, dates, algorithm, self-signed). That metadata may go to the report; PEM must not.

### `Test-ImcLeafKeyPair` (702–720)

Path B only. Derives the public key from the cert and from the key (`openssl x509 -pubkey` vs `openssl pkey -pubout`) and compares. A mismatch can take HTTPS down on activate. Key bytes are not logged.

### `Get-ImcPemFileText` (722–734)

Reads the file **at upload time** for PowerTool `content-cert-upload`. Warns if the payload is larger than typical IMC paste caps (~8 KB). Callers must not pass the return value to `Write-ImcOpLog`.

### `Get-ImcRemotePwd` (736–742)

PowerTool’s `-Pwd` parameter is a **string**. This unwraps `PSCredential.GetNetworkCredential().Password` for that cmdlet call only. It does **not** use `ConvertTo-SecureString -AsPlainText` (that pattern is banned: it is how people hardcode passwords). Do not log the return value. Memory only.

---

## 8. Connect, retry, reconnect (lines 744–876)

### Why `PSCredential` stays in memory

Project preference: prompt **once**, reuse for every CSV host and for reconnect after a cert change, never write the password to disk / CSV / report / log. A `[PSCredential]` is the PowerShell type designed for that. The script stores it in a hashtable (`$scriptBound.Credential`) that helpers can update by reference (hashtables are reference types).

### `Test-ImcLoginFailureMessage` (744–751)

Heuristic on exception text / `FullyQualifiedErrorId`: authentication vs network. Network errors should not trigger a credential prompt; auth failures should, and the prompt must **name the CIMC address**.

### `Read-ImcApplyCredentialToRemaining` (753–770)

After a successful re-prompt, ask `Y/N` whether the replacement credential applies to the rest of the CSV. Logs YES/NO, never the password.

### `Connect-ImcTarget` (772–779)

Thin wrapper around `Connect-Imc -Name -Credential`. Comment notes PowerTool’s default **InvalidCertificateAction = Ignore**, which is required *during* rotation (the old or new cert may not match the browser name yet). Ignore is **not** proof of browser trust.

### `Connect-ImcTargetWithRetry` (781–827)

1. Try in-memory credential.
2. On auth failure: `Get-Credential` with the failed address in the message.
3. On success: optionally copy the new credential onto `$Bound.Credential` for remaining hosts (`HostCredential` always records what this host used).
4. Non-auth failures throw (redacted).

`$Bound` is a hashtable passed into every host invocation so retry logic can mutate the run-wide credential without a dozen `ref` parameters.

### `Disconnect-ImcQuiet` (829–831)

`Disconnect-Imc` swallowing errors. Used in `finally` so a failed host does not leave a session open for the next row.

### `Wait-ImcReconnect` (833–876)

After Path A upload or Path B activate, IMC drops **HTTPS and SSH** (management-plane restart, not a host OS reboot). This function:

1. Warns and disconnects.
2. Sleeps `$ReconnectWaitSeconds` (default 90).
3. Retries connect until a deadline; on first auth failure, re-prompts (named host) and may update remaining-host credential.
4. Throws with “recover from CIMC CLI or serial” if the deadline passes.

Keep serial/SoL available — that is an operator concern; the code’s job is to wait, retry, and fail loudly.

---

## 9. IMC inventory, CSR, upload, Path B (lines 878–1116)

### `Get-ImcControllerFirmwareInfo` (878–900)

`Get-ImcFirmwareRunning`, then pick `blade-controller` + `system` (fallbacks if those fields differ). Parse with `ConvertFrom-ImcFirmwareString`. If parse fails: **throw**. Guessing Path B on an unknown string is how you brick HTTPS on an old IMC.

### `Get-ImcCurrentCertSummary` (902–911)

`Receive-ImcCertificate` → CN, issuer CN, serial, validity. Report columns `CommonName` / `ValidTo` come from here (or from preflight before connect). No PEM.

### `Add-ImcSanToSplat` (913–943)

Cisco.IMC CSR cmdlet wants `SubjectAltNameType1` / `SubjectAltNameValue1` … up to **10**. This helper turns `DNS:name`, `IP:addr`, or a bare IP/DNS into those numbered parameters. IMC GUI limit is 10 total.

### `Invoke-ImcCsrGenerate` (945–992) — Path A

Builds a splat for `New-ImcCertificateSigningRequest` (CN/O/OU/L/S/C required; `&` forbidden in CN/OU). Optional remote share: CSR is dropped via SCP/SFTP (`-User` / `-Pwd` from share credential, not logged). Without a share, the CSR is generated on IMC and **not printed** (copy from GUI/CLI).

**ShouldProcess:** `ShouldProcess($Target.ImcAddress, "Generate HTTPS CSR (Path A) CN=...")` before `New-ImcCertificateSigningRequest`. `-WhatIf` returns `WhatIf: CSR generate skipped.`

Warns to set IMC NTP first: a wrong clock produces a CSR with a bad validity window.

### `Invoke-ImcCsrUpload` (994–1042) — Path A

Either:

- `Send-ImcCertificate -AdminAction remote-cert-upload` (IMC pulls from share), or
- `content-cert-upload` with `Get-ImcPemFileText` (local path).

`Send-ImcCertificate` often **throws because the session dropped** — that can be success. The catch logs a redacted warning, then `Wait-ImcReconnect`, then `Get-ImcCurrentCertSummary`. Clients still need the issuing CA; PowerTool Ignore is not browser trust.

Gated by `ShouldProcess` on the target address.

### `Wait-ImcExternalUpload` (1044–1062)

Path B uploads are asynchronous. Poll `Get-ImcUploadExternalCertificate` or `Get-ImcUploadExternalPrivateKey` for about two minutes. Fail on `fail|error`; return on `complete`.

### `Invoke-ImcExternalImport` (1064–1116) — Path B

Requires local cert+key paths, or remote share with **both** remote cert and remote key files (SCP/SFTP only for the key). Order:

1. `Set-ImcUploadExternalCertificate` (remote or content)
2. Wait until complete
3. `Set-ImcUploadExternalPrivateKey` (same)
4. Wait until complete
5. `Get-ImcCertificateManagement` then `Set-ImcManagedObject -PropertyMap @{ AdminAction = 'activate-external-cert' } -Force`

There is no `Set-ImcCertificateManagement` on Gallery 3.0.6.23 — that is why activate goes through `Set-ImcManagedObject`. Activate drops HTTPS/SSH; catch-and-reconnect is the same pattern as Path A upload.

`ShouldProcess` wraps the whole upload+activate so `-WhatIf` skips all of it.

---

## 10. Per-host orchestration — `Invoke-ImcHttpsCertificateHost` (lines 1118–1242)

This is the **one host** function. Main only loops; this function owns skip, preflight, connect, **firmware branch**, method dispatch, and disconnect.

Result object (also a report row): `Timestamp`, `ImcAddress`, `Hostname`, `Firmware`, `Method`, `Path`, `Result`, `Reason`, `CommonName`, `ValidTo`. `Result` is `Success` / `Failed` / `Skipped`.

Flow:

1. If `Target.SkipReason` (bad CSV row) → `Skipped`, return. No login.
2. Resolve per-row paths and ExpectedName over script parameters.
3. For `CsrUpload` / `ExternalImport`: openssl preflight unless `-SkipCertificatePreflight`. For Path B: key file + key-pair match.
4. `Connect-ImcTargetWithRetry`.
5. `try` / `finally` (`Disconnect-ImcQuiet` always).
6. **Firmware branch** (the version policy in code):
   - Read/parse controller firmware.
   - Below `4.0.4`: `Skipped` unless `-ContinueOnOldFirmware` (then warn; Path B still refused below 4.1.2).
   - Snapshot current cert (`Receive-ImcCertificate`).
   - `$pathBCapable = $fw.Version -ge [version]'4.1.2'`.
7. **Method branch:**
   - `Inventory` — no cert change. `Path` is `A-or-B` or `A`. Annotate `-WhatIf` if set. Success.
   - `ExternalImport` — if not `$pathBCapable`, `Failed` with `Path = B-refused` (do not attempt). Else `Invoke-ImcExternalImport`.
   - `CsrGenerate` / `CsrUpload` — Path A. `Invoke-ImcCsrGenerate` / `Invoke-ImcCsrUpload`.
8. WhatIf-ish return strings (`^WhatIf`) become `Skipped` so the report does not claim Success for a dry run.

**Why version branch lives here, not in `param()`.** Firmware is unknown until you are logged in. `ValidateSet` cannot encode “this host is 4.1.1.” Inventory is allowed on every in-floor host so operators can see Path A vs A-or-B before they choose a method.

---

## 11. Main (lines 1244–1361)

After all functions are defined, execution falls through here. This is the script’s `main`.

1. **`Get-ImcReportPathPair`** — create log immediately so later failures still have a file.
2. **Credential prompt** if `-Credential` omitted: `Get-Credential` once, message says “reused for every CSV host” or names the single address. Cancel → error and `return` (no plain-text password fallback).
3. **Remote share credential** if remote paths are set.
4. Extra refuse of sha1/md5 signature algorithms.
5. **`$scriptBound` hashtable** — snapshot of parameters plus `Credential` and `HostCredential`. Passed into every host call. Helpers mutate `Credential` when the operator says “use this for remaining hosts.”
6. **`Get-ImcTargetList`** — CSV or single host. Failures here abort the run (no hosts to process).
7. **CSV loop** (`foreach ($t in $targets)`):
   - Log `=== Host i/N ===`.
   - `Invoke-ImcHttpsCertificateHost`.
   - On `Failed` + `$stopOnError`, throw (honors `-ErrorAction Stop`).
   - On unexpected exception: redact, append a Failed row, disconnect, throw only if `$stopOnError`, else continue.
8. **`Export-Csv`** the collected rows (`-NoTypeInformation`, UTF-8). Counts Success/Failed/Skipped.
9. **`Write-Output`** a summary object (`ReportPath`, `LogPath`, counts) so callers and the console see where to look.

That loop is the fleet requirement: one method, many CIMCs, per-host reason, keep going after a failure.

---

## Patterns — why they exist (quick reference)

| Pattern | Where | Why |
| --- | --- | --- |
| `#Requires -Version 7.4` | Line 1 | Project floor so UCS and Intersight share one runtime (`pwsh`). Engine-enforced. |
| Banner + comment-based help | 2–233 | Banner for Git readers; `<# .SYNOPSIS #>` for `Get-Help`. Disclaimer in both plus runtime `Write-Warning`. |
| `[CmdletBinding]` + `param()` | 235–344 | Advanced script: common parameters, validation, `$PSCmdlet`. Public API in one place. |
| Functions, then main | 396–1242 then 1244+ | Named units; entry point at the bottom; helpers registered before they are called. |
| `SupportsShouldProcess` / `ShouldProcess` | Binding; generate/upload/activate | `-WhatIf` / `-Confirm` on changes. Inventory still connects (read). |
| `PSCredential` in memory | Main + connect/retry | Prompt once; reuse for CSV and reconnect; never disk; never `-AsPlainText`. Re-prompt names the failing IMC. |
| Instruct-only PS/module | 360–394 | Do not `winget` / `Install-Module` from automation. Print commands and stop. |
| CSV loop + skip rows | `Get-ImcTargetList`, main foreach | Fleet: one method, many hosts; bad rows recorded; continue unless `-ErrorAction Stop`. |
| Report CSV + sidecar log | `Get-ImcReportPathPair`, `Write-ImcOpLog`, `Export-Csv` | Per-host Result/Reason; no passwords/PEM. Log is incremental; CSV is end-of-run. |
| Firmware version branch | `Invoke-ImcHttpsCertificateHost` | 4.0.4 floor; Path B only ≥ 4.1.2; unknown version → refuse, do not guess. |
| Redaction | `Get-ImcRedactedText` | Exceptions must not leak PEM or passwords into the log or Reason column. |
| `$scriptBound` hashtable | Main → host → connect | Reference-type bag so retry can update the run-wide credential. |

---

## What not to add when you edit this script

- Passwords, API keys, `ConvertTo-SecureString -AsPlainText`, or `-----BEGIN` material (including in comments and examples).
- `Install-Module`, `Update-Module`, `winget`, or any PowerShell upgrade inside the script.
- TFTP/FTP/HTTP for private keys; PKCS #12 upload; encrypted key upload; printing CSR/cert/key PEM.
- A guessed Path B on unparsed firmware.
- Silent continue on Path B below 4.1.2.
- KMIP, LDAP CA, mTLS, SPDM, or UCS Manager FI HTTPS — out of scope.

Cmdlets this script actually uses (Gallery 3.0.6.23): `Connect-Imc`, `Disconnect-Imc`, `Get-ImcFirmwareRunning`, `Receive-ImcCertificate`, `New-ImcCertificateSigningRequest`, `Send-ImcCertificate`, `Set-ImcUploadExternalCertificate`, `Get-ImcUploadExternalCertificate`, `Set-ImcUploadExternalPrivateKey`, `Get-ImcUploadExternalPrivateKey`, `Get-ImcCertificateManagement`, `Set-ImcManagedObject`.

---

## Related files

- Operator runbook: `Update-ImcHttpsCertificate-README.md` (same folder when James copies the set).
- Project emit rules: `powershell-script-standard.md`.
- Script: `Update-ImcHttpsCertificate.ps1`.
