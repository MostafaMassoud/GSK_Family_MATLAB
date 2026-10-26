# Builds the HTML documentation site for gsk_family.
#
# Renders with Pandoc 3.8 or newer. If Pandoc is missing or older than 3.8
# (no --syntax-highlighting option), a small built-in Markdown-to-HTML
# fallback is used, so the script always produces a working site. If Doxygen
# is available it builds the C++ API reference, linked from the sidebar.
# Mermaid diagrams render in the browser with mermaid.js.
#
# Sources: the tracked Markdown files under docs/ (the source of truth),
# LICENSES.md, and RUNBOOK.md and NEW_VARIANT_GUIDE.md in the repository root
# (one level above gsk_family). Pages whose source is missing are skipped with
# a warning.
# Output:  docs/html/ (generated; gitignored), plus RUNBOOK.html and
#          NEW_VARIANT_GUIDE.html next to their Markdown (tracked; commit
#          each with its .md). Rebuild with one command:
#
#   powershell -File scripts\build_docs.ps1
#
# Options:
#   -Doxygen <path>   doxygen executable (else 'doxygen' on PATH; skipped if absent)
#   -Pandoc  <path>   pandoc executable  (else 'pandoc' on PATH; fallback if absent or < 3.8)
#   -Clean            remove docs/html before building

param(
    [string]$Doxygen = "",
    [string]$Pandoc = "",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$docsDir = Join-Path $projectRoot "docs"
$outDir = Join-Path $docsDir "html"

function Resolve-Tool([string]$given, [string]$name) {
    # Returns the given path if it exists, else the tool on PATH, else ""
    # (the caller then uses the fallback renderer or skips the API docs).
    # A bad path gives a warning here instead of a crash later.
    if ($given -ne "") {
        if (Test-Path $given) { return $given }
        Write-Warning "$name path '$given' not found; falling back to PATH."
    }
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return ""
}
$pandocExe = Resolve-Tool $Pandoc "pandoc"
$doxygenExe = Resolve-Tool $Doxygen "doxygen"

# The Pandoc call below passes --syntax-highlighting=none, added in Pandoc 3.8;
# older versions reject it ("Unknown option") and the build would stop on the
# first page. An older or unidentifiable Pandoc is treated as missing: the
# fallback renderer is used and a warning at the end says why.
$pandocMinVersion = [version]"3.8"
$pandocRejected = ""
if ($pandocExe -ne "") {
    $pandocVersion = $null
    try {
        $verLine = & $pandocExe --version | Select-Object -First 1
        if ("$verLine" -match '^pandoc(?:\.exe)?\s+(\d+)\.(\d+)') {
            $pandocVersion = [version]("{0}.{1}" -f $Matches[1], $Matches[2])
        }
    } catch { }
    if ($null -eq $pandocVersion -or $pandocVersion -lt $pandocMinVersion) {
        $found = if ($null -eq $pandocVersion) { "unknown version" } else { "version $pandocVersion" }
        $pandocRejected = "Pandoc at '$pandocExe' is $found; $pandocMinVersion or newer is required"
        $pandocExe = ""
    }
}

if ($Clean -and (Test-Path $outDir)) { Remove-Item -Recurse -Force $outDir }
New-Item -ItemType Directory -Force $outDir | Out-Null

# ---- Page list ----
# In sidebar order, by group. Out is a flat file name: every page sits at the
# top of docs/html, so pages link to each other without ../ paths.
$pages = @(
    @{ Src = "docs/index.md"; Out = "index.html"; Title = "Home"; Group = "" },

    @{ Src = "../RUNBOOK.md";                           Out = "runbook.html";                         Title = "Runbook";         Group = "Getting Started" },
    @{ Src = "../NEW_VARIANT_GUIDE.md";                 Out = "new_variant_guide.html";               Title = "New Variant Guide"; Group = "Getting Started" },
    @{ Src = "docs/getting-started/explainer.md";       Out = "getting-started_explainer.html";       Title = "Explainer";       Group = "Getting Started" },
    @{ Src = "docs/getting-started/tutorial.md";        Out = "getting-started_tutorial.html";        Title = "Tutorial";        Group = "Getting Started" },
    @{ Src = "docs/getting-started/user_guide.md";      Out = "getting-started_user_guide.html";      Title = "User Guide";      Group = "Getting Started" },
    @{ Src = "docs/getting-started/command_reference.md"; Out = "getting-started_command_reference.html"; Title = "Command Reference"; Group = "Getting Started" },
    @{ Src = "docs/getting-started/configuration.md";   Out = "getting-started_configuration.html";   Title = "Configuration";   Group = "Getting Started" },
    @{ Src = "docs/getting-started/troubleshooting.md"; Out = "getting-started_troubleshooting.html"; Title = "Troubleshooting"; Group = "Getting Started" },

    @{ Src = "docs/reference/architecture.md";        Out = "reference_architecture.html";        Title = "Architecture";               Group = "Reference" },
    @{ Src = "docs/reference/matlab_interface.md";    Out = "reference_matlab_interface.html";    Title = "MATLAB Optimizer Interface"; Group = "Reference" },
    @{ Src = "docs/reference/api.md";                 Out = "reference_api.html";                 Title = "C++ API (how-to)";           Group = "Reference" },
    @{ Src = "docs/reference/module_dependencies.md"; Out = "reference_module_dependencies.html"; Title = "Module Dependencies";        Group = "Reference" },
    @{ Src = "docs/reference/workflows.md";           Out = "reference_workflows.html";           Title = "Workflows";                  Group = "Reference" },
    @{ Src = "docs/reference/result_schema.md";       Out = "reference_result_schema.html";       Title = "Result Schema";              Group = "Reference" },
    @{ Src = "docs/reference/seed_policy.md";         Out = "reference_seed_policy.html";         Title = "Seed Policy";                Group = "Reference" },
    @{ Src = "docs/reference/benchmark_protocol.md";  Out = "reference_benchmark_protocol.html";  Title = "Benchmark Protocol";         Group = "Reference" },
    @{ Src = "docs/reference/benchmark_mapping.md";   Out = "reference_benchmark_mapping.html";   Title = "Benchmark Mapping";          Group = "Reference" },
    @{ Src = "docs/reference/diagrams.md";            Out = "reference_diagrams.html";            Title = "Diagrams";                   Group = "Reference" },
    @{ Src = "docs/reference/project_structure.md";   Out = "reference_project_structure.html";   Title = "Project Structure";          Group = "Reference" },
    @{ Src = "docs/reference/reference_inventory.md"; Out = "reference_reference_inventory.html"; Title = "Provenance Inventory";       Group = "Reference" },
    @{ Src = "docs/reference/porting_notes.md";       Out = "reference_porting_notes.html";       Title = "Porting Notes";              Group = "Reference" },
    @{ Src = "docs/reference/cec2011_port_plan.md";   Out = "reference_cec2011_port_plan.html";   Title = "CEC2011 Port Plan";          Group = "Reference" },
    @{ Src = "docs/reference/glossary.md";            Out = "reference_glossary.html";            Title = "Glossary";                   Group = "Reference" },
    @{ Src = "LICENSES.md";                           Out = "LICENSES.html";                      Title = "License and Provenance";     Group = "Reference" },

    @{ Src = "docs/algorithms/gsk.md";        Out = "algorithms_gsk.html";        Title = "GSK";        Group = "Algorithm Guides" },
    @{ Src = "docs/algorithms/agsk.md";       Out = "algorithms_agsk.html";       Title = "AGSK";       Group = "Algorithm Guides" },
    @{ Src = "docs/algorithms/apgsk.md";      Out = "algorithms_apgsk.html";      Title = "APGSK";      Group = "Algorithm Guides" },
    @{ Src = "docs/algorithms/fdb-agsk.md";   Out = "algorithms_fdb-agsk.html";   Title = "FDB-AGSK";   Group = "Algorithm Guides" },
    @{ Src = "docs/algorithms/atmals-gsk.md"; Out = "algorithms_atmals-gsk.html"; Title = "ATMALS-GSK"; Group = "Algorithm Guides" },
    @{ Src = "docs/algorithms/egsk.md";       Out = "algorithms_egsk.html";       Title = "eGSK";       Group = "Algorithm Guides" },
    @{ Src = "docs/algorithms/dt-gsk.md";     Out = "algorithms_dt-gsk.html";     Title = "DT-GSK";     Group = "Algorithm Guides" },

    @{ Src = "docs/development/developer_guide.md";             Out = "development_developer_guide.html";             Title = "Developer Guide";            Group = "Development" },
    @{ Src = "docs/development/contributor_guide.md";           Out = "development_contributor_guide.html";           Title = "Contributor Guide";          Group = "Development" },
    @{ Src = "docs/development/maintenance_guide.md";           Out = "development_maintenance_guide.html";           Title = "Maintenance Guide";          Group = "Development" },
    @{ Src = "docs/development/extension_guide.md";             Out = "development_extension_guide.html";             Title = "Extension Guide";            Group = "Development" },
    @{ Src = "docs/development/code_reading_guide.md";          Out = "development_code_reading_guide.html";          Title = "Code Reading Guide";         Group = "Development" },

    @{ Src = "docs/prompts/REVIEW_PROMPT.md";                Out = "prompts_REVIEW_PROMPT.html";                Title = "Full Project Review Prompt";     Group = "Prompts" },
    @{ Src = "docs/prompts/DOCS_DEEP_REVIEW_PROMPT.md";      Out = "prompts_DOCS_DEEP_REVIEW_PROMPT.html";      Title = "Deep Documentation Prompt";     Group = "Prompts" },
    @{ Src = "docs/prompts/documentation_review_prompt.md";  Out = "prompts_documentation_review_prompt.html";  Title = "Documentation Review Prompt";   Group = "Prompts" },
    @{ Src = "docs/prompts/INLINE_DOCUMENTATION_REVIEW_PROMPT.md"; Out = "prompts_INLINE_DOCUMENTATION_REVIEW_PROMPT.html"; Title = "Inline Documentation Prompt"; Group = "Prompts" },
    @{ Src = "docs/prompts/documentation_parity_prompt.md";  Out = "prompts_documentation_parity_prompt.html";  Title = "Documentation Parity Prompt";   Group = "Prompts" },
    @{ Src = "docs/prompts/llm_review_prompt.md";            Out = "prompts_llm_review_prompt.html";            Title = "Legacy LLM Review Prompt";      Group = "Prompts" },

    @{ Src = "docs/research/researcher_handbook.md"; Out = "research_researcher_handbook.html"; Title = "Researcher Handbook"; Group = "Research" },
    @{ Src = "docs/research/comparing_algorithms.md"; Out = "research_comparing_algorithms.html"; Title = "Comparing Algorithms"; Group = "Research" },
    @{ Src = "docs/research/reproducibility.md";     Out = "research_reproducibility.html";     Title = "Reproducibility";     Group = "Research" },
    @{ Src = "docs/research/performance.md";         Out = "research_performance.html";         Title = "Performance";         Group = "Research" },
    @{ Src = "docs/research/validation_report.md";   Out = "research_validation_report.html";   Title = "Validation Report";   Group = "Research" },
    @{ Src = "docs/research/numerical_examples.md";  Out = "research_numerical_examples.html";  Title = "Numerical Examples";  Group = "Research" }
)

# Absolute source path -> flat output name, for rewriting cross-links.
$srcToOut = @{}
foreach ($p in $pages) {
    $abs = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $p.Src))
    $srcToOut[$abs.ToLowerInvariant()] = $p.Out
}

# Fallback map keyed by file basename. A page may still carry an old relative
# link (e.g. ../explainer.md); when the full-path lookup misses, Repair-Html
# uses this map. Every source basename in $pages is unique, so it is
# unambiguous.
$baseToOut = @{}
foreach ($p in $pages) {
    $base = [System.IO.Path]::GetFileName($p.Src).ToLowerInvariant()
    if (-not $baseToOut.ContainsKey($base)) { $baseToOut[$base] = $p.Out }
}

# ---- Sidebar nav (the same on every page) ----
$navSb = [System.Text.StringBuilder]::new()
$lastGroup = $null
foreach ($p in $pages) {
    if ($p.Group -eq "") { continue }
    if ($p.Group -ne $lastGroup) {
        if ($null -ne $lastGroup) { [void]$navSb.Append('</ul>') }
        [void]$navSb.Append('<div class="navgroup">' + $p.Group + '</div><ul>')
        $lastGroup = $p.Group
    }
    [void]$navSb.Append('<li><a href="' + $p.Out + '">' + ($p.Title -replace '&', '&amp;') + '</a></li>')
}
if ($null -ne $lastGroup) { [void]$navSb.Append('</ul>') }
[void]$navSb.Append('<div class="navgroup">C++ API</div><ul><li><a href="api/index.html">C++ API (Doxygen)</a></li></ul>')
$nav = $navSb.ToString()

$css = @'
/* gsk_family documentation theme - clean, readable, light + dark.
   Written to docs/html/style.css by scripts/build_docs.ps1. */
:root{
  --content-width:760px; --sidebar-width:264px; --toc-width:220px;
  --bg:#ffffff; --bg-elevated:#ffffff; --sidebar-bg:#fbfbfa;
  --fg:#2c3137; --fg-muted:#5b636d; --fg-faint:#8a929c;
  --border:#e7e9ed; --border-strong:#d6d9df;
  --accent:#2563eb; --accent-soft:#eef3ff;
  --code-bg:#f6f7f9; --code-fg:#2a2f36; --code-border:#e9ebef;
  --table-head-bg:#f4f6f8; --table-zebra:#fafbfc;
  --callout-bg:#f2f7ff; --callout-border:#bcd3ff;
  --shadow-md:0 10px 34px rgba(18,26,40,.16);
  color-scheme:light;
}
html.theme-dark{
  --bg:#0f1419; --bg-elevated:#161c24; --sidebar-bg:#11161d;
  --fg:#d2d8df; --fg-muted:#98a2ae; --fg-faint:#6b7682;
  --border:#232a33; --border-strong:#323b46;
  --accent:#6aa3ff; --accent-soft:#172539;
  --code-bg:#161c24; --code-fg:#c9d1d9; --code-border:#262d37;
  --table-head-bg:#161d26; --table-zebra:#131921;
  --callout-bg:#13202f; --callout-border:#26456e;
  --shadow-md:0 12px 38px rgba(0,0,0,.55);
  color-scheme:dark;
}
*,*::before,*::after{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
  font-size:17px;line-height:1.7;color:var(--fg);background:var(--bg);-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}

/* top bar */
.topbar{position:sticky;top:0;z-index:30;display:flex;align-items:center;gap:12px;height:56px;padding:0 18px;
  background:var(--bg);border-bottom:1px solid var(--border)}
.topbar .brand{display:flex;align-items:center;gap:9px;font-weight:700;font-size:16px;letter-spacing:-.01em;color:var(--fg);text-decoration:none}
.topbar .brand .dot{width:11px;height:11px;border-radius:3px;background:var(--accent)}
.topbar .spacer{flex:1}
.iconbtn{display:inline-flex;align-items:center;justify-content:center;width:38px;height:38px;border:1px solid var(--border);
  background:var(--bg-elevated);color:var(--fg-muted);border-radius:9px;cursor:pointer;font-size:16px;line-height:1}
.iconbtn:hover{color:var(--fg);border-color:var(--border-strong)}
#menuBtn{display:none}

/* layout */
.layout{display:flex;align-items:flex-start}
nav.sidebar{position:sticky;top:56px;width:var(--sidebar-width);flex:0 0 var(--sidebar-width);
  height:calc(100vh - 56px);overflow-y:auto;background:var(--sidebar-bg);border-right:1px solid var(--border);padding:20px 14px 40px}
nav.sidebar .navgroup{margin:18px 10px 6px;font-size:11.5px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--fg-faint)}
nav.sidebar .navgroup:first-child{margin-top:2px}
nav.sidebar ul{list-style:none;margin:0 0 2px;padding:0}
nav.sidebar li a{display:block;padding:6px 10px;margin:1px 0;color:var(--fg-muted);text-decoration:none;border-radius:7px;font-size:14.5px;line-height:1.35}
nav.sidebar li a:hover{background:var(--accent-soft);color:var(--fg)}
nav.sidebar li a.active{background:var(--accent-soft);color:var(--accent);font-weight:600;box-shadow:inset 2px 0 0 var(--accent)}

main{flex:1;min-width:0;display:flex;justify-content:center;gap:36px;padding:34px 40px 80px}
article{width:100%;max-width:var(--content-width);min-width:0}

/* right toc */
#TOC{position:sticky;top:80px;align-self:flex-start;width:var(--toc-width);flex:0 0 var(--toc-width);
  max-height:calc(100vh - 110px);overflow:auto;font-size:13.5px;line-height:1.5;border-left:1px solid var(--border);padding-left:18px}
#TOC .toc-title{font-size:11.5px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--fg-faint);margin-bottom:8px}
#TOC ul{list-style:none;margin:0;padding-left:14px}
#TOC>ul{padding-left:0}
#TOC li{margin:3px 0}
#TOC a{color:var(--fg-muted);text-decoration:none}
#TOC a:hover{color:var(--accent)}

/* typography */
article h1,article h2,article h3,article h4{line-height:1.3;font-weight:700;letter-spacing:-.01em;scroll-margin-top:72px}
article h1{font-size:32px;margin:0 0 .55em;padding-bottom:.35em;border-bottom:1px solid var(--border)}
article h2{font-size:24px;margin:2em 0 .6em;padding-bottom:.3em;border-bottom:1px solid var(--border)}
article h3{font-size:19px;margin:1.7em 0 .5em}
article h4{font-size:16px;margin:1.5em 0 .4em}
article p{margin:0 0 1.05em}
article ul,article ol{margin:0 0 1.05em;padding-left:1.5em}
article li{margin:.3em 0}
article li::marker{color:var(--fg-faint)}
article ol>li::marker{color:var(--fg-muted);font-weight:600}
article hr{border:0;border-top:1px solid var(--border);margin:2em 0}
strong{font-weight:700;color:var(--fg)}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline;text-underline-offset:2px}

/* code */
code{font-family:"Cascadia Code","JetBrains Mono",Consolas,"SF Mono",Menlo,monospace;font-size:.88em;
  background:var(--code-bg);color:var(--code-fg);padding:.13em .4em;border-radius:5px;border:1px solid var(--code-border)}
pre{background:var(--code-bg);color:var(--code-fg);padding:16px 18px;border-radius:10px;overflow:auto;
  border:1px solid var(--code-border);margin:0 0 1.2em;font-size:14px;line-height:1.6}
pre code{background:none;border:0;padding:0;font-size:inherit}
.code-wrap{position:relative;margin:0 0 1.2em}
.code-wrap pre{margin:0}
.copy-btn{position:absolute;top:8px;right:8px;font-size:12px;padding:3px 9px;border-radius:6px;
  border:1px solid var(--border-strong);background:var(--bg-elevated);color:var(--fg-muted);cursor:pointer;opacity:.55;transition:opacity .12s}
.code-wrap:hover .copy-btn{opacity:1}
.copy-btn:hover{color:var(--fg)}
.copy-btn.copied{color:#1a7f37;border-color:#1a7f37}

/* tables */
.table-wrap{overflow-x:auto;margin:0 0 1.3em;border:1px solid var(--border);border-radius:10px}
table{border-collapse:collapse;width:100%;font-size:14.5px}
th,td{padding:9px 14px;text-align:left;border-bottom:1px solid var(--border)}
thead th{background:var(--table-head-bg);font-weight:600;color:var(--fg);border-bottom:2px solid var(--border-strong);white-space:nowrap}
tbody tr:nth-child(even){background:var(--table-zebra)}
tbody tr:last-child td{border-bottom:0}

/* callouts */
blockquote{margin:0 0 1.2em;padding:.6em 1.1em;background:var(--callout-bg);border:1px solid var(--callout-border);
  border-left:4px solid var(--accent);border-radius:8px;color:var(--fg)}
blockquote p:last-child{margin-bottom:0}

/* mermaid + images */
.mermaid{margin:1.4em 0;padding:14px;text-align:center;background:var(--bg-elevated);border:1px solid var(--border);border-radius:10px;overflow-x:auto}
article img{max-width:100%;height:auto;border-radius:8px}

/* footer */
footer{margin-top:56px;padding-top:18px;border-top:1px solid var(--border);color:var(--fg-faint);font-size:13px}

/* mobile nav scrim */
.scrim{display:none;position:fixed;inset:56px 0 0 0;z-index:18;background:rgba(10,15,22,.42)}

/* responsive */
@media(max-width:1180px){#TOC{display:none}}
@media(max-width:920px){
  #menuBtn{display:inline-flex}
  nav.sidebar{position:fixed;top:56px;left:0;z-index:20;transform:translateX(-100%);transition:transform .2s ease;box-shadow:var(--shadow-md)}
  body.nav-open nav.sidebar{transform:translateX(0)}
  body.nav-open .scrim{display:block}
  main{padding:24px 20px 64px}
  body{font-size:16.5px}
}
@media(max-width:560px){
  main{padding:20px 16px 56px}
  article h1{font-size:27px}
  article h2{font-size:21px}
}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}nav.sidebar{transition:none}}
'@

# ---- Browser helpers: theme toggle, mobile nav, active link, copy button ----
# Written to docs/html/app.js. No dependencies and no '$' characters (kept
# clear of Pandoc template variables).
$js = @'
/* gsk_family docs - small UX helpers (theme, nav, copy). No dependencies. */
(function () {
  "use strict";
  var root = document.documentElement;
  function currentTheme() { return root.classList.contains("theme-dark") ? "dark" : "light"; }
  function applyTheme(mode) {
    if (mode === "dark") { root.classList.add("theme-dark"); } else { root.classList.remove("theme-dark"); }
    var b = document.getElementById("themeBtn");
    if (b) {
      b.textContent = mode === "dark" ? "L" : "D";
      b.setAttribute("aria-label", mode === "dark" ? "Switch to light theme" : "Switch to dark theme");
    }
  }
  applyTheme(currentTheme());
  var themeBtn = document.getElementById("themeBtn");
  if (themeBtn) {
    themeBtn.addEventListener("click", function () {
      var next = currentTheme() === "dark" ? "light" : "dark";
      try { localStorage.setItem("theme", next); } catch (e) {}
      applyTheme(next);
    });
  }

  var body = document.body;
  var menuBtn = document.getElementById("menuBtn");
  var scrim = document.querySelector(".scrim");
  function closeNav() { body.classList.remove("nav-open"); }
  if (menuBtn) { menuBtn.addEventListener("click", function () { body.classList.toggle("nav-open"); }); }
  if (scrim) { scrim.addEventListener("click", closeNav); }

  var here = location.pathname.split("/").pop() || "index.html";
  var links = document.querySelectorAll("nav.sidebar a");
  for (var i = 0; i < links.length; i++) {
    if ((links[i].getAttribute("href") || "") === here) { links[i].classList.add("active"); }
    links[i].addEventListener("click", closeNav);
  }

  function fallbackCopy(text, done) {
    var ta = document.createElement("textarea");
    ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
    document.body.appendChild(ta); ta.focus(); ta.select();
    try { document.execCommand("copy"); done(); } catch (e) {}
    document.body.removeChild(ta);
  }
  var pres = document.querySelectorAll("article pre");
  for (var j = 0; j < pres.length; j++) {
    var pre = pres[j];
    if (pre.classList.contains("mermaid")) { continue; }
    var wrap = document.createElement("div");
    wrap.className = "code-wrap";
    pre.parentNode.insertBefore(wrap, pre);
    wrap.appendChild(pre);
    var btn = document.createElement("button");
    btn.className = "copy-btn"; btn.type = "button"; btn.textContent = "Copy";
    wrap.appendChild(btn);
    btn.addEventListener("click", (function (p, b) {
      return function () {
        var text = p.innerText;
        var done = function () {
          b.textContent = "Copied"; b.classList.add("copied");
          setTimeout(function () { b.textContent = "Copy"; b.classList.remove("copied"); }, 1500);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done, function () { fallbackCopy(text, done); });
        } else { fallbackCopy(text, done); }
      };
    })(pre, btn));
  }
})();
'@

# ---- Pandoc HTML template ----
# The inline head script applies the saved or preferred theme before the first
# paint (no flash). __NAV__ is replaced with the sidebar nav below. style.css
# and app.js are written once into docs/html (below).
$template = @'
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title$ - gsk_family</title>
<link rel="stylesheet" href="style.css">
<script>
(function(){try{var t=localStorage.getItem('theme');
if(!t){t=(window.matchMedia&&window.matchMedia('(prefers-color-scheme:dark)').matches)?'dark':'light';}
if(t==='dark'){document.documentElement.className+=' theme-dark';}}catch(e){}})();
</script>
</head><body>
<header class="topbar">
<button id="menuBtn" class="iconbtn" type="button" aria-label="Toggle navigation">&#9776;</button>
<a class="brand" href="index.html"><span class="dot"></span>gsk_family</a>
<span class="spacer"></span>
<button id="themeBtn" class="iconbtn" type="button" aria-label="Toggle theme">D</button>
</header>
<div class="layout">
<nav class="sidebar">__NAV__</nav>
<div class="scrim"></div>
<main>
<article>
$body$
<footer>gsk_family documentation &middot; &copy; 2026 Mostafa Elsayed Ahmed Masoud, Cairo University &middot; <a href="https://orcid.org/0009-0003-8415-2158">ORCID 0009-0003-8415-2158</a> &middot; please cite this framework and the algorithm papers you use &middot; generated by scripts/build_docs.ps1</footer>
</article>
$if(toc)$<aside id="TOC"><div class="toc-title">On this page</div>$table-of-contents$</aside>$endif$
</main>
</div>
<script src="app.js" defer></script>
<script type="module">
import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs";
mermaid.initialize({ startOnLoad: true, theme: document.documentElement.classList.contains('theme-dark') ? 'dark' : 'neutral' });
</script>
</body></html>
'@

# Write the shared stylesheet and script once into the output root, as UTF-8
# without a BOM. Every page links them as style.css and app.js.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $outDir 'style.css'), $css, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outDir 'app.js'), $js, $utf8NoBom)

$templateResolved = $template.Replace("__NAV__", $nav)
$templatePath = Join-Path $env:TEMP "gskcec_doc_template.html"
[System.IO.File]::WriteAllText($templatePath, $templateResolved, $utf8NoBom)

# ---- Fallback Markdown-to-HTML (used when Pandoc is missing or < 3.8) ----
# Handles only #..#### headings, - / * lists, fenced code, `code`, **bold**,
# links and paragraphs. No tables and no page TOC.
function Convert-MarkdownFallback([string]$md) {
    $lines = $md -split "`r?`n"
    $html = [System.Text.StringBuilder]::new()
    $inCode = $false; $inList = $false
    foreach ($ln in $lines) {
        if ($ln -match '^```') {
            if (-not $inCode) { [void]$html.Append('<pre><code>'); $inCode = $true } else { [void]$html.Append('</code></pre>'); $inCode = $false }
            continue
        }
        if ($inCode) { [void]$html.AppendLine([System.Web.HttpUtility]::HtmlEncode($ln)); continue }
        $e = [System.Web.HttpUtility]::HtmlEncode($ln)
        $e = [regex]::Replace($e, '`([^`]+)`', '<code>$1</code>')
        $e = [regex]::Replace($e, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
        $e = [regex]::Replace($e, '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>')
        if ($e -match '^(#{1,4})\s+(.*)') { $lvl = $matches[1].Length; [void]$html.Append("<h$lvl>$($matches[2])</h$lvl>"); continue }
        if ($e -match '^\s*[-*]\s+(.*)') { if (-not $inList) { [void]$html.Append('<ul>'); $inList = $true }; [void]$html.Append("<li>$($matches[1])</li>"); continue }
        if ($inList) { [void]$html.Append('</ul>'); $inList = $false }
        if ($e.Trim() -eq '') { [void]$html.Append('') } else { [void]$html.Append("<p>$e</p>") }
    }
    if ($inList) { [void]$html.Append('</ul>') }
    if ($inCode) { [void]$html.Append('</code></pre>') }
    return $html.ToString()
}
Add-Type -AssemblyName System.Web

# ---- Post-process: cross-page links (.md -> flat .html), mermaid, tables ----
function Repair-Html([string]$html, [string]$srcDir) {
    # href="...something.md[#anchor]" -> flat output name. URLs and unknown
    # targets are left unchanged.
    $html = [regex]::Replace($html, 'href="([^"]+?\.md)(#[^"]*)?"', {
        param($m)
        $target = $m.Groups[1].Value; $anchor = $m.Groups[2].Value
        if ($target -match '^[a-z]+://') { return $m.Value }
        $abs = ""
        try { $abs = [System.IO.Path]::GetFullPath((Join-Path $srcDir $target)).ToLowerInvariant() } catch { return $m.Value }
        if ($srcToOut.ContainsKey($abs)) { return 'href="' + $srcToOut[$abs] + $anchor + '"' }
        $base = [System.IO.Path]::GetFileName($target).ToLowerInvariant()
        if ($baseToOut.ContainsKey($base)) { return 'href="' + $baseToOut[$base] + $anchor + '"' }
        return $m.Value
    })
    # Pandoc emits <pre class="mermaid"><code>...</code></pre>; mermaid.js wants
    # the diagram text directly inside <pre class="mermaid">.
    $html = [regex]::Replace($html, '<pre class="mermaid"><code>(.*?)</code></pre>', '<pre class="mermaid">$1</pre>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    # Wrap tables so wide ones scroll inside a frame instead of overflowing
    # the article column.
    $html = [regex]::Replace($html, '(<table[\s\S]*?</table>)', '<div class="table-wrap">$1</div>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    return $html
}

# ---- Convert each page ----
$built = 0; $skipped = @()
foreach ($p in $pages) {
    $srcPath = Join-Path $projectRoot $p.Src
    if (-not (Test-Path $srcPath)) { $skipped += $p.Src; continue }
    $srcDir = Split-Path -Parent ([System.IO.Path]::GetFullPath($srcPath))
    $outPath = Join-Path $outDir $p.Out
    if ($pandocExe -ne "") {
        & $pandocExe $srcPath -f gfm -t html5 -s --syntax-highlighting=none --template $templatePath --toc --toc-depth=3 `
            -M title="$($p.Title)" -o $outPath
        if ($LASTEXITCODE -ne 0) { throw "pandoc failed on $($p.Src)" }
        $html = [System.IO.File]::ReadAllText($outPath, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($outPath, (Repair-Html $html $srcDir), $utf8NoBom)
    } else {
        $body = Convert-MarkdownFallback ([System.IO.File]::ReadAllText($srcPath, [System.Text.Encoding]::UTF8))
        $page = $templateResolved.Replace('$title$', $p.Title).Replace('$body$', $body) `
            -replace '\$if\(toc\)\$.*?\$endif\$', ''
        [System.IO.File]::WriteAllText($outPath, (Repair-Html $page $srcDir), $utf8NoBom)
    }
    $built++
}

# ---- Standalone guide pages next to their Markdown (repository root) ----
# RUNBOOK.md -> RUNBOOK.html and NEW_VARIANT_GUIDE.md -> NEW_VARIANT_GUIDE.html:
# self-contained pages (no external files, work offline) that a newcomer can
# open straight from the repository. The first heading becomes the page
# title. A small script adds the contents sidebar highlight, step numbers,
# copy buttons, a reading-progress bar and a light/dark switch. Links between
# the root guides point to their .html files; links to other Markdown files
# stay as they are, so they work in any checkout.
$rootPages = @(
    @{ Src = "../RUNBOOK.md"; Eyebrow = "Step-by-step guide";
       Subtitle = "Set up the project, run the seven GSK optimizers on the CEC benchmark suites, and turn the results into convergence figures and statistical tables. No prior knowledge of the code is needed.";
       Chips = @("MATLAB + C++", "5 CEC suites", "7 GSK optimizers", "Figures and statistics") },
    @{ Src = "../NEW_VARIANT_GUIDE.md"; Eyebrow = "Researcher guide";
       Subtitle = "Create your own GSK variant in this project, check it, run it on the CEC suites next to the family, and produce the figures and tables for your manuscript.";
       Chips = @("One command to start", "Fair same-seed comparison", "Any CEC suite", "Paper-ready output") }
)
$rootNav = @(
    @{ Href = "RUNBOOK.html"; Title = "Runbook" },
    @{ Href = "NEW_VARIANT_GUIDE.html"; Title = "New Variant Guide" }
)
$rootTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title$ - GSK Family</title>
<script>
(function () { var t = null; try { t = localStorage.getItem('gsk-theme'); } catch (e) {}
  if (t === 'light' || t === 'dark') { document.documentElement.setAttribute('data-theme', t); } })();
</script>
<style>
:root{
  --bg:#f6f7fb;--card:#ffffff;--fg:#1a1f2b;--muted:#5a6375;--border:#e2e6ee;--soft:#f1f3f8;
  --accent:#4f46e5;--accent-2:#0891b2;--accent-soft:#eef0ff;--code:#eceff5;--pre:#0f172a;--pre-fg:#e2e8f0;
  --note:#2563eb;--tip:#059669;--important:#7c3aed;--warning:#d97706;--caution:#dc2626;
  --shadow:0 1px 2px rgba(16,24,40,.04),0 6px 24px rgba(16,24,40,.06);color-scheme:light}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
  --bg:#0b0f19;--card:#121826;--fg:#e6e9f2;--muted:#9aa3b5;--border:#242c3d;--soft:#171e2e;
  --accent:#8b93ff;--accent-2:#22d3ee;--accent-soft:#1c2140;--code:#1d2435;--pre:#0a0e17;--pre-fg:#e2e8f0;
  --note:#60a5fa;--tip:#34d399;--important:#a78bfa;--warning:#fbbf24;--caution:#f87171;
  --shadow:0 1px 2px rgba(0,0,0,.3),0 8px 28px rgba(0,0,0,.35);color-scheme:dark}}
:root[data-theme="dark"]{
  --bg:#0b0f19;--card:#121826;--fg:#e6e9f2;--muted:#9aa3b5;--border:#242c3d;--soft:#171e2e;
  --accent:#8b93ff;--accent-2:#22d3ee;--accent-soft:#1c2140;--code:#1d2435;--pre:#0a0e17;--pre-fg:#e2e8f0;
  --note:#60a5fa;--tip:#34d399;--important:#a78bfa;--warning:#fbbf24;--caution:#f87171;
  --shadow:0 1px 2px rgba(0,0,0,.3),0 8px 28px rgba(0,0,0,.35);color-scheme:dark}
*{box-sizing:border-box}
html{scroll-behavior:smooth;scroll-padding-top:76px}
body{margin:0;background:var(--bg);color:var(--fg);font:16.5px/1.7 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;-webkit-font-smoothing:antialiased}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}
.wrap{max-width:1180px;margin:0 auto;padding:0 24px}
#progress{position:fixed;top:0;left:0;height:3px;width:0;background:linear-gradient(90deg,var(--accent),var(--accent-2));z-index:60}
.topbar{position:sticky;top:0;z-index:50;background:color-mix(in srgb,var(--bg) 82%,transparent);backdrop-filter:saturate(1.6) blur(10px);-webkit-backdrop-filter:saturate(1.6) blur(10px);border-bottom:1px solid var(--border)}
.topbar .wrap{display:flex;align-items:center;gap:18px;height:58px}
.brand{display:flex;align-items:center;gap:10px;font-weight:700;color:var(--fg);letter-spacing:-.01em}
.brand:hover{text-decoration:none}
.logo{width:28px;height:28px;border-radius:8px;background:linear-gradient(135deg,var(--accent),var(--accent-2));display:grid;place-items:center;color:#fff;font-size:13px;font-weight:800}
.links{display:flex;gap:4px;margin-left:auto}
.links a{color:var(--muted);font-size:.92rem;font-weight:550;padding:6px 12px;border-radius:8px}
.links a:hover{background:var(--soft);color:var(--fg);text-decoration:none}
.links a.here{color:var(--accent);background:var(--accent-soft)}
#theme{border:1px solid var(--border);background:var(--card);color:var(--fg);width:36px;height:36px;border-radius:10px;cursor:pointer;font-size:16px;display:grid;place-items:center}
#theme:hover{border-color:var(--accent)}
.hero{position:relative;overflow:hidden;color:#fff;background:radial-gradient(1200px 400px at 85% -10%,rgba(255,255,255,.18),transparent 60%),radial-gradient(800px 300px at 0% 120%,rgba(34,211,238,.35),transparent 60%),linear-gradient(135deg,#3730a3 0%,#4f46e5 45%,#0e7490 100%)}
.hero .wrap{padding-top:64px;padding-bottom:58px}
.hero::after{content:"";position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.06) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.06) 1px,transparent 1px);background-size:32px 32px;mask-image:linear-gradient(180deg,rgba(0,0,0,.7),transparent);-webkit-mask-image:linear-gradient(180deg,rgba(0,0,0,.7),transparent);pointer-events:none}
.eyebrow{display:inline-block;margin:0 0 14px;padding:4px 12px;border-radius:999px;background:rgba(255,255,255,.16);border:1px solid rgba(255,255,255,.28);font-size:.8rem;font-weight:650;letter-spacing:.06em;text-transform:uppercase}
h1.title{font-size:clamp(2.1rem,4.6vw,3.2rem);line-height:1.1;margin:0 0 14px;letter-spacing:-.025em;font-weight:800}
.subtitle{max-width:760px;font-size:1.15rem;line-height:1.6;margin:0;color:rgba(255,255,255,.9)}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:24px}
.chips span{font-size:.85rem;font-weight:600;padding:6px 12px;border-radius:999px;background:rgba(15,23,42,.28);border:1px solid rgba(255,255,255,.22)}
.layout{display:grid;grid-template-columns:260px minmax(0,1fr);gap:40px;padding-top:36px;padding-bottom:80px}
.sidebar{position:relative}
#TOC{position:sticky;top:82px;max-height:calc(100vh - 100px);overflow:auto;padding:4px 4px 12px 0;font-size:.9rem}
.toc-title{margin:0 0 8px;font-size:.75rem;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--muted)}
#TOC ul{list-style:none;margin:0;padding:0}
#TOC>ul>li{margin:2px 0}
#TOC li ul{margin:2px 0 6px 14px;border-left:1px solid var(--border)}
#TOC li ul a{font-size:.85rem;padding:3px 10px}
#TOC a{display:block;color:var(--muted);padding:5px 10px;border-radius:8px;line-height:1.35}
#TOC a:hover{color:var(--fg);background:var(--soft);text-decoration:none}
#TOC a.active{color:var(--accent);background:var(--accent-soft);font-weight:650}
#TOC .num{display:inline-grid;place-items:center;min-width:20px;height:20px;margin-right:7px;border-radius:6px;background:var(--soft);font-size:.72rem;font-weight:700;color:var(--muted)}
#TOC a.active .num{background:var(--accent);color:#fff}
.toc-toggle{display:none}
main{min-width:0}
.lead{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:22px 28px;box-shadow:var(--shadow);margin-bottom:28px;font-size:1.04rem}
.lead>:first-child{margin-top:0}.lead>:last-child{margin-bottom:0}
section.level1{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:8px 32px 26px;margin:0 0 28px;box-shadow:var(--shadow)}
section.level1>h1{display:flex;align-items:center;gap:14px;font-size:1.55rem;line-height:1.25;margin:22px 0 14px;letter-spacing:-.015em}
h1 .num{flex:none;display:grid;place-items:center;width:40px;height:40px;border-radius:12px;background:linear-gradient(135deg,var(--accent),var(--accent-2));color:#fff;font-size:1.05rem;font-weight:800;box-shadow:0 4px 14px color-mix(in srgb,var(--accent) 35%,transparent)}
h2{font-size:1.18rem;margin:1.8em 0 .5em;letter-spacing:-.01em}
h3{font-size:1.02rem;margin:1.5em 0 .4em}
p,ul,ol{margin:.75em 0}
li{margin:.3em 0}
li>p{margin:.3em 0}
strong{font-weight:680}
code{font:.86em/1.5 ui-monospace,"Cascadia Code","SFMono-Regular",Consolas,"Liberation Mono",monospace;background:var(--code);padding:.14em .42em;border-radius:6px}
:not(pre)>code{overflow-wrap:anywhere}
pre{position:relative;background:var(--pre);color:var(--pre-fg);border-radius:12px;padding:40px 18px 16px;overflow-x:auto;margin:1.1em 0;border:1px solid rgba(148,163,184,.18)}
pre code{background:none;padding:0;color:inherit;font-size:.86em;line-height:1.6}
pre .lang{position:absolute;top:10px;left:16px;font:700 .68rem/1 -apple-system,"Segoe UI",sans-serif;letter-spacing:.08em;text-transform:uppercase;color:#94a3b8}
.copy{position:absolute;top:7px;right:8px;font:600 12px/1 -apple-system,"Segoe UI",sans-serif;padding:6px 10px;border:1px solid rgba(148,163,184,.3);border-radius:8px;background:rgba(148,163,184,.12);color:#cbd5e1;cursor:pointer}
.copy:hover{background:rgba(148,163,184,.25);color:#fff}
.copy.done{color:#86efac;border-color:#86efac}
table{border-collapse:separate;border-spacing:0;display:block;overflow-x:auto;margin:1.2em 0;font-size:.93em;border:1px solid var(--border);border-radius:12px}
th,td{padding:10px 14px;text-align:left;vertical-align:top;border-bottom:1px solid var(--border)}
tr:last-child td{border-bottom:0}
th{background:var(--soft);font-weight:680;white-space:nowrap}
tbody tr:nth-child(even) td{background:color-mix(in srgb,var(--soft) 55%,transparent)}
hr{border:0;border-top:1px solid var(--border);margin:2em 0}
blockquote{margin:1.1em 0;padding:4px 18px;border-left:4px solid var(--border);color:var(--muted)}
div.note,div.tip,div.important,div.warning,div.caution{--c:var(--note);margin:1.2em 0;padding:12px 18px 12px 18px;border:1px solid color-mix(in srgb,var(--c) 35%,var(--border));border-left:4px solid var(--c);border-radius:12px;background:color-mix(in srgb,var(--c) 8%,var(--card))}
div.tip{--c:var(--tip)}div.important{--c:var(--important)}div.warning{--c:var(--warning)}div.caution{--c:var(--caution)}
div.title p{margin:0 0 4px;font-weight:750;font-size:.82rem;letter-spacing:.06em;text-transform:uppercase;color:var(--c)}
div.note>:last-child,div.tip>:last-child,div.important>:last-child,div.warning>:last-child,div.caution>:last-child{margin-bottom:0}
div.flow ol{list-style:none;counter-reset:flow;display:flex;flex-wrap:wrap;gap:10px;padding:0;margin:1.2em 0}
div.flow li{counter-increment:flow;position:relative;flex:1 1 150px;margin:0;padding:14px 14px 14px 52px;background:var(--soft);border:1px solid var(--border);border-radius:12px;font-size:.92rem;line-height:1.45}
div.flow li::before{content:counter(flow);position:absolute;left:14px;top:13px;width:26px;height:26px;border-radius:8px;display:grid;place-items:center;background:linear-gradient(135deg,var(--accent),var(--accent-2));color:#fff;font-weight:800;font-size:.8rem}
div.flow li strong{display:block;color:var(--fg)}
div.cards ul{list-style:none;padding:0;display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin:1.2em 0}
div.cards li{margin:0;padding:16px 18px;background:var(--soft);border:1px solid var(--border);border-radius:12px;font-size:.93rem;line-height:1.5}
div.cards li strong{display:block;font-size:1rem;margin-bottom:2px}
details{margin:1.1em 0;padding:4px 18px;border:1px solid var(--border);border-radius:12px;background:var(--soft)}
details[open]{padding-bottom:10px}
summary{cursor:pointer;font-weight:650;padding:8px 0}
footer.page{color:var(--muted);font-size:.85rem;margin-top:40px;padding-top:18px;border-top:1px solid var(--border)}
#totop{position:fixed;right:22px;bottom:22px;width:44px;height:44px;border-radius:12px;border:1px solid var(--border);background:var(--card);color:var(--fg);box-shadow:var(--shadow);cursor:pointer;font-size:18px;opacity:0;pointer-events:none;transition:opacity .2s}
#totop.show{opacity:1;pointer-events:auto}
@media (max-width:1000px){
  .layout{grid-template-columns:1fr;gap:0;padding-top:20px}
  .sidebar{margin-bottom:18px}
  .toc-toggle{display:flex;width:100%;justify-content:space-between;align-items:center;padding:12px 16px;border:1px solid var(--border);border-radius:12px;background:var(--card);color:var(--fg);font:650 .95rem/1 inherit;cursor:pointer;box-shadow:var(--shadow)}
  #TOC{position:static;max-height:none;display:none;margin-top:8px;padding:12px;background:var(--card);border:1px solid var(--border);border-radius:12px}
  #TOC.open{display:block}
  .toc-title{display:none}
  .links{display:none}}
@media (max-width:640px){
  body{font-size:16px}.wrap{padding:0 16px}
  .hero .wrap{padding-top:40px;padding-bottom:40px}
  section.level1{padding:4px 18px 18px;border-radius:14px}
  .lead{padding:16px 18px}
  section.level1>h1{font-size:1.3rem}
  td code{white-space:nowrap;overflow-wrap:normal}
  h1 .num{width:34px;height:34px}}
@media print{
  .topbar,#progress,#totop,.sidebar,.copy{display:none!important}
  .hero{background:none;color:#000}.hero::after{display:none}.subtitle{color:#333}.eyebrow,.chips span{border-color:#999;background:none}
  .layout{display:block}section.level1,.lead{box-shadow:none;break-inside:auto}
  pre{white-space:pre-wrap;background:#f4f4f4;color:#000}body{font-size:11pt;background:#fff}}
</style>
</head>
<body>
<div id="progress" aria-hidden="true"></div>
<header class="topbar"><div class="wrap">
  <a class="brand" href="#top"><span class="logo">G</span>GSK Family</a>
  <nav class="links" aria-label="Guides">$for(nav)$<a href="$nav.href$">$nav.title$</a>$endfor$</nav>
  <button id="theme" type="button" aria-label="Switch light or dark theme" title="Light / dark">&#9680;</button>
</div></header>
<section class="hero" id="top"><div class="wrap">
  <p class="eyebrow">$eyebrow$</p>
  <h1 class="title">$title$</h1>
  <p class="subtitle">$subtitle$</p>
  <div class="chips">$for(chip)$<span>$chip$</span>$endfor$</div>
</div></section>
<div class="layout wrap">
<aside class="sidebar">
$if(toc)$
<nav id="TOC" aria-label="Contents"><p class="toc-title">On this page</p>
$table-of-contents$
</nav>
$endif$
</aside>
<main id="content">
$body$
<footer class="page"><strong>&copy; 2026 Mostafa Elsayed Ahmed Masoud</strong>, PhD Candidate in Operations Research, Department of Operations Research, Faculty of Graduate Studies for Statistical Research, Cairo University, Giza 12613, Egypt &middot; <a href="https://orcid.org/0009-0003-8415-2158">ORCID 0009-0003-8415-2158</a> &middot; <a href="mailto:moustafa.masoud@gmail.com">moustafa.masoud@gmail.com</a><br>If you use this framework, please cite it and the papers of the algorithms you use (gsk_family/CITATION.cff, gsk_family/LICENSES.md).<br>This page is generated from $source$ by gsk_family/scripts/build_docs.ps1. To change it, edit $source$ and rebuild.</footer>
</main>
</div>
<button id="totop" type="button" aria-label="Back to top">&#8593;</button>
<script>
(function () {
  var main = document.getElementById('content');
  // Intro text before the first section becomes one lead card (a Markdown
  // horizontal rule there is only a separator).
  var first = main.querySelector('section.level1');
  if (first) {
    var lead = document.createElement('div'); lead.className = 'lead';
    while (main.firstChild && main.firstChild !== first) {
      var n = main.firstChild;
      if (n.nodeType === 1 && n.tagName === 'HR') { main.removeChild(n); continue; }
      lead.appendChild(n);
    }
    if (lead.textContent.trim()) { main.insertBefore(lead, first); }
  }
  // "6. Title" headings and contents entries get a number badge.
  function badge(el, cls) {
    var m = /^(\d+)\.\s+/.exec(el.textContent);
    if (!m || !el.firstChild || el.firstChild.nodeType !== 3) { return; }
    el.firstChild.nodeValue = el.firstChild.nodeValue.replace(/^\s*\d+\.\s+/, '');
    var s = document.createElement('span'); s.className = cls; s.textContent = m[1];
    el.insertBefore(s, el.firstChild);
  }
  document.querySelectorAll('section.level1 > h1').forEach(function (h) { badge(h, 'num'); });
  document.querySelectorAll('#TOC > ul > li > a').forEach(function (a) { badge(a, 'num'); });
  // Mark the current guide in the top bar.
  var page = location.pathname.split('/').pop();
  document.querySelectorAll('.links a').forEach(function (a) {
    if (a.getAttribute('href') === page) { a.classList.add('here'); }
  });
  // Code blocks: language label and copy button.
  var names = {matlab: 'MATLAB', powershell: 'PowerShell', bash: 'Bash', sh: 'Shell', text: 'Text', latex: 'LaTeX', tex: 'LaTeX'};
  document.querySelectorAll('pre').forEach(function (pre) {
    var lang = (pre.className || '').split(/\s+/)[0];
    var l = document.createElement('span'); l.className = 'lang';
    l.textContent = names[lang] || (lang ? lang : 'Code'); pre.appendChild(l);
    var b = document.createElement('button');
    b.className = 'copy'; b.type = 'button'; b.textContent = 'Copy';
    b.addEventListener('click', function () {
      var code = pre.querySelector('code'), text = (code || pre).innerText;
      var done = function () { b.textContent = 'Copied'; b.classList.add('done');
        setTimeout(function () { b.textContent = 'Copy'; b.classList.remove('done'); }, 1500); };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () { selectText(code || pre); });
      } else { selectText(code || pre); }
    });
    pre.appendChild(b);
  });
  function selectText(el) {
    var r = document.createRange(); r.selectNodeContents(el);
    var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
  }
  // Contents: collapsible on narrow screens, current section highlighted.
  var toc = document.getElementById('TOC');
  if (toc) {
    var t = document.createElement('button'); t.className = 'toc-toggle'; t.type = 'button';
    t.innerHTML = '<span>Contents</span><span>&#9662;</span>';
    t.addEventListener('click', function () { toc.classList.toggle('open'); });
    toc.parentNode.insertBefore(t, toc);
    toc.addEventListener('click', function (e) { if (e.target.closest('a')) { toc.classList.remove('open'); } });
    var links = Array.prototype.slice.call(toc.querySelectorAll('a'));
    var targets = links.map(function (a) { return document.getElementById(decodeURIComponent(a.getAttribute('href').slice(1))); });
    var spy = function () {
      var y = window.scrollY + 100, cur = -1;
      targets.forEach(function (el, i) { if (el && el.getBoundingClientRect().top + window.scrollY <= y) { cur = i; } });
      links.forEach(function (a, i) { a.classList.toggle('active', i === cur); });
    };
    window.addEventListener('scroll', spy, {passive: true});
    window.addEventListener('load', spy); window.addEventListener('hashchange', spy);
    spy(); setTimeout(spy, 250);   // after a jump to #section on opening
  }
  // Reading progress and back-to-top.
  var bar = document.getElementById('progress'), up = document.getElementById('totop');
  var onScroll = function () {
    var h = document.documentElement, max = h.scrollHeight - h.clientHeight;
    bar.style.width = (max > 0 ? 100 * h.scrollTop / max : 0) + '%';
    up.classList.toggle('show', h.scrollTop > 600);
  };
  window.addEventListener('scroll', onScroll, {passive: true}); onScroll();
  up.addEventListener('click', function () { window.scrollTo({top: 0, behavior: 'smooth'}); });
  // Light / dark switch (remembered in this browser when storage is allowed).
  document.getElementById('theme').addEventListener('click', function () {
    var root = document.documentElement, cur = root.getAttribute('data-theme');
    if (!cur) { cur = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'; }
    var next = cur === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('gsk-theme', next); } catch (e) {}
  });
})();
</script>
</body>
</html>
'@
$rootBuilt = @()
foreach ($rp in $rootPages) {
    $rpSrc = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $rp.Src))
    if (-not (Test-Path $rpSrc)) { continue }
    $rpOut = [System.IO.Path]::ChangeExtension($rpSrc, ".html")
    $rpName = [System.IO.Path]::GetFileName($rpSrc)
    if ($pandocExe -ne "") {
        $rpTemplatePath = Join-Path $env:TEMP "gskcec_root_page_template.html"
        [System.IO.File]::WriteAllText($rpTemplatePath, $rootTemplate, $utf8NoBom)
        $rpMeta = Join-Path $env:TEMP "gskcec_root_page_meta.json"
        $meta = @{ eyebrow = $rp.Eyebrow; subtitle = $rp.Subtitle; chip = $rp.Chips; source = $rpName;
                   nav = @($rootNav | ForEach-Object { @{ href = $_.Href; title = $_.Title } }) }
        # Variables go in as JSON metadata (Pandoc escapes them as plain text).
        [System.IO.File]::WriteAllText($rpMeta, ($meta | ConvertTo-Json -Depth 4), $utf8NoBom)
        & $pandocExe $rpSrc -f gfm -t html5 -s --syntax-highlighting=none --template $rpTemplatePath `
            --metadata-file=$rpMeta --section-divs --shift-heading-level-by=-1 --toc --toc-depth=2 -o $rpOut
        if ($LASTEXITCODE -ne 0) { throw "pandoc failed on $rpName" }
    } else {
        $md = [System.IO.File]::ReadAllText($rpSrc, [System.Text.Encoding]::UTF8)
        $rpTitle = ([regex]::Match($md, '^#\s+([^\r\n]*)')).Groups[1].Value
        $md = [regex]::Replace($md, '^#\s+[^\r\n]*\r?\n', '')   # the title is printed by the template
        $page = $rootTemplate.Replace('$title$', $rpTitle).Replace('$eyebrow$', $rp.Eyebrow).
            Replace('$subtitle$', $rp.Subtitle).Replace('$source$', $rpName).Replace('$body$', (Convert-MarkdownFallback $md))
        $page = [regex]::Replace($page, '(?s)\$if\(toc\)\$.*?\$endif\$', '')
        $page = [regex]::Replace($page, '(?s)\$for\(chip\)\$.*?\$endfor\$', (($rp.Chips | ForEach-Object { "<span>$_</span>" }) -join ''))
        $page = [regex]::Replace($page, '(?s)\$for\(nav\)\$.*?\$endfor\$', (($rootNav | ForEach-Object { "<a href=""$($_.Href)"">$($_.Title)</a>" }) -join ''))
        [System.IO.File]::WriteAllText($rpOut, $page, $utf8NoBom)
    }
    # Links between the root guides open their HTML pages.
    $html = [System.IO.File]::ReadAllText($rpOut, [System.Text.Encoding]::UTF8)
    foreach ($nv in $rootNav) {
        $mdName = [System.IO.Path]::ChangeExtension($nv.Href, ".md")
        $html = $html.Replace("href=""$mdName""", "href=""$($nv.Href)""").Replace("href=""$mdName#", "href=""$($nv.Href)#")
    }
    [System.IO.File]::WriteAllText($rpOut, $html, $utf8NoBom)
    $rootBuilt += $rpOut
}

# ---- Doxygen C++ API into docs/html/api ----
$apiBuilt = $false
if ($doxygenExe -ne "" -and (Test-Path (Join-Path $docsDir "Doxyfile"))) {
    Push-Location $projectRoot
    try {
        # Temp copy of the Doxyfile with overrides appended:
        # - OUTPUT_DIRECTORY/HTML_OUTPUT -> docs/html/api, whatever the Doxyfile
        #   says. Only api/ is regenerated; other docs/html pages are untouched.
        # - HAVE_DOT=NO: Graphviz is optional and often missing, and without it
        #   Doxygen errors on every graph. Call/include graphs are omitted.
        # Written as UTF-8 WITHOUT a BOM: a BOM makes Doxygen fail with
        # "unknown character" at line 1.
        $cfg = [System.IO.File]::ReadAllText((Join-Path $docsDir "Doxyfile"), [System.Text.Encoding]::UTF8) +
               "`nOUTPUT_DIRECTORY=docs/html`nHTML_OUTPUT=api`nGENERATE_LATEX=NO`nHAVE_DOT=NO`nSEARCHENGINE=NO`nQUIET=YES`n"
        $tmpCfg = Join-Path $env:TEMP "gskcec_Doxyfile.tmp"
        [System.IO.File]::WriteAllText($tmpCfg, $cfg, (New-Object System.Text.UTF8Encoding($false)))
        # Doxygen writes warnings to stderr. With $ErrorActionPreference='Stop'
        # the merged 2>&1 stream raises a terminating error that stops Doxygen
        # after only the crawl file. So relax it for this call and send all
        # Doxygen output to a log file.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        # Keep the log (it records absolute source paths) out of docs/html, so
        # the site has no machine-specific paths.
        $doxLog = Join-Path $env:TEMP "gskcec_doxygen.log"
        & $doxygenExe $tmpCfg > $doxLog 2>&1
        $ErrorActionPreference = $prevEap
        if (Test-Path (Join-Path $outDir "api/index.html")) { $apiBuilt = $true }
    } catch { Write-Warning "Doxygen step failed: $_" }
    finally { Pop-Location }
}

Write-Host ("build_docs: {0} page(s) -> {1}" -f $built, $outDir)
foreach ($rb in $rootBuilt) { Write-Host ("build_docs: standalone page -> {0}" -f $rb) }
if ($pandocRejected -ne "") { Write-Warning "$pandocRejected; used the minimal fallback renderer (upgrade Pandoc for full fidelity)." }
elseif ($pandocExe -eq "") { Write-Warning "Pandoc not found; used the minimal fallback renderer (install Pandoc for full fidelity)." }
if (-not $apiBuilt) { Write-Warning "C++ API (Doxygen) not generated; the API link will 404 until 'doxygen docs/Doxyfile' is available." }
if ($skipped.Count -gt 0) { Write-Warning ("Skipped missing source(s): " + ($skipped -join ", ")) }
Write-Host ("Open: " + (Join-Path $outDir "index.html"))
