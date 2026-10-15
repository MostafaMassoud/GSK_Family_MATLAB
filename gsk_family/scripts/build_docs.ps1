# Builds the comprehensive HTML documentation site for gsk_family.
#
# No Python (project contract). Primary renderer is Pandoc 3.8 or newer; if
# Pandoc is absent, or older than 3.8 (it lacks --syntax-highlighting), a
# built-in minimal Markdown->HTML fallback is used so the script always
# produces a navigable site. Doxygen (if present) generates the C++ API
# reference and is linked in. Mermaid diagrams render client-side via mermaid.js.
#
# Sources: the tracked Markdown files under docs/ (the source of truth).
# Output:  docs/html/ (generated; gitignored). Rebuild with one command:
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
    # An explicitly-passed path is only honored if it exists; otherwise fall
    # back to PATH (and then to "" -> the documented degraded path) instead of
    # crashing later when the tool is invoked.
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

# The Pandoc call below passes --syntax-highlighting=none, an option added in
# Pandoc 3.8; older releases reject it ("Unknown option") and would abort the
# build on the first page. Treat an older (or unidentifiable) Pandoc like a
# missing one: use the built-in fallback renderer and say why at the end.
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

# ---- Page list: ordered, grouped; Out is a FLAT html name so all pages sit at
# the top of docs/html and link to each other without ../ depth juggling. -------
$pages = @(
    @{ Src = "docs/index.md"; Out = "index.html"; Title = "Home"; Group = "" },

    @{ Src = "docs/getting-started/explainer.md";       Out = "getting-started_explainer.html";       Title = "Explainer";       Group = "Getting Started" },
    @{ Src = "docs/getting-started/tutorial.md";        Out = "getting-started_tutorial.html";        Title = "Tutorial";        Group = "Getting Started" },
    @{ Src = "docs/getting-started/user_guide.md";      Out = "getting-started_user_guide.html";      Title = "User Guide";      Group = "Getting Started" },
    @{ Src = "docs/getting-started/runbook.md";         Out = "getting-started_runbook.html";         Title = "Runbook";         Group = "Getting Started" },
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
    @{ Src = "docs/research/reproducibility.md";     Out = "research_reproducibility.html";     Title = "Reproducibility";     Group = "Research" },
    @{ Src = "docs/research/performance.md";         Out = "research_performance.html";         Title = "Performance";         Group = "Research" },
    @{ Src = "docs/research/validation_report.md";   Out = "research_validation_report.html";   Title = "Validation Report";   Group = "Research" },
    @{ Src = "docs/research/numerical_examples.md";  Out = "research_numerical_examples.html";  Title = "Numerical Examples";  Group = "Research" }
)

# Map absolute source path -> flat output name, for rewriting cross-links.
$srcToOut = @{}
foreach ($p in $pages) {
    $abs = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $p.Src))
    $srcToOut[$abs.ToLowerInvariant()] = $p.Out
}

# Fallback map keyed by unique file basename. Pages now live in subfolders, so a
# moved page may still carry an old relative link (e.g. ../explainer.md). When the
# resolved-path lookup misses, Repair-Html falls back to this basename map. Every
# source basename in $pages is unique, so this is unambiguous.
$baseToOut = @{}
foreach ($p in $pages) {
    $base = [System.IO.Path]::GetFileName($p.Src).ToLowerInvariant()
    if (-not $baseToOut.ContainsKey($base)) { $baseToOut[$base] = $p.Out }
}

# ---- Sidebar nav (shared by every page). --------------------------------------
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

# ---- Browser-side UX helpers: theme toggle, mobile nav, active link, copy. -----
# Written to docs/html/app.js. No dependencies, no '$' tokens (kept out of the
# pandoc template's variable namespace).
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

# ---- Pandoc HTML template -----------------------------------------------------
# The inline head script applies the saved/preferred theme before first paint
# (no flash). style.css and app.js are written once into docs/html (below).
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
<footer>gsk_family documentation &middot; generated by scripts/build_docs.ps1</footer>
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

# Write the shared stylesheet and script once into the output root. Flat pages
# reference them as ./style.css and ./app.js. UTF-8 without BOM.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $outDir 'style.css'), $css, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outDir 'app.js'), $js, $utf8NoBom)

$templateResolved = $template.Replace("__NAV__", $nav)
$templatePath = Join-Path $env:TEMP "gskcec_doc_template.html"
[System.IO.File]::WriteAllText($templatePath, $templateResolved, $utf8NoBom)

# ---- Minimal fallback Markdown->HTML (used if Pandoc is absent or < 3.8). ------
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

# ---- Rewrite cross-page links (.md -> flat .html) and fix mermaid blocks. ------
function Repair-Html([string]$html, [string]$srcDir) {
    # href="...something.md[#anchor]"  ->  flat output name
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
    # Wrap tables so wide ones scroll inside a rounded frame instead of
    # overflowing the article column.
    $html = [regex]::Replace($html, '(<table[\s\S]*?</table>)', '<div class="table-wrap">$1</div>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    return $html
}

# ---- Convert each page. -------------------------------------------------------
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

# ---- Doxygen C++ API into docs/html/api. --------------------------------------
$apiBuilt = $false
if ($doxygenExe -ne "" -and (Test-Path (Join-Path $docsDir "Doxyfile"))) {
    Push-Location $projectRoot
    try {
        # Override output to docs/html/api regardless of the Doxyfile setting.
        # Write a temp config as UTF-8 WITHOUT a BOM (a BOM makes Doxygen choke
        # on "unknown character" at line 1).
        # OUTPUT_DIRECTORY/HTML_OUTPUT -> docs/html/api (Doxygen only regenerates
        # the api/ subdir; the other docs/html pages are left untouched).
        # HAVE_DOT=NO: Graphviz is optional and often absent; without it Doxygen
        # would error on every graph. Disabling it yields clean, fast HTML
        # (call/include graphs are simply omitted).
        $cfg = [System.IO.File]::ReadAllText((Join-Path $docsDir "Doxyfile"), [System.Text.Encoding]::UTF8) +
               "`nOUTPUT_DIRECTORY=docs/html`nHTML_OUTPUT=api`nGENERATE_LATEX=NO`nHAVE_DOT=NO`nSEARCHENGINE=NO`nQUIET=YES`n"
        $tmpCfg = Join-Path $env:TEMP "gskcec_Doxyfile.tmp"
        [System.IO.File]::WriteAllText($tmpCfg, $cfg, (New-Object System.Text.UTF8Encoding($false)))
        # Doxygen writes warnings to stderr; with $ErrorActionPreference='Stop'
        # the merged 2>&1 stream would raise a terminating error and kill
        # Doxygen after only the crawl file. Relax it for this call and send
        # Doxygen's output to a log instead of the error stream.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        # Keep the doxygen run log (which records absolute source paths) OUT of
        # docs/html so the generated site stays free of machine-specific paths.
        $doxLog = Join-Path $env:TEMP "gskcec_doxygen.log"
        & $doxygenExe $tmpCfg > $doxLog 2>&1
        $ErrorActionPreference = $prevEap
        if (Test-Path (Join-Path $outDir "api/index.html")) { $apiBuilt = $true }
    } catch { Write-Warning "Doxygen step failed: $_" }
    finally { Pop-Location }
}

Write-Host ("build_docs: {0} page(s) -> {1}" -f $built, $outDir)
if ($pandocRejected -ne "") { Write-Warning "$pandocRejected; used the minimal fallback renderer (upgrade Pandoc for full fidelity)." }
elseif ($pandocExe -eq "") { Write-Warning "Pandoc not found; used the minimal fallback renderer (install Pandoc for full fidelity)." }
if (-not $apiBuilt) { Write-Warning "C++ API (Doxygen) not generated; the API link will 404 until 'doxygen docs/Doxyfile' is available." }
if ($skipped.Count -gt 0) { Write-Warning ("Skipped missing source(s): " + ($skipped -join ", ")) }
Write-Host ("Open: " + (Join-Path $outDir "index.html"))
