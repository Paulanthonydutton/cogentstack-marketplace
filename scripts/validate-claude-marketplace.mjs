import { spawnSync } from "node:child_process";
import { readdir, readFile } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const marketplacePath = join(repositoryRoot, ".claude-plugin", "marketplace.json");
const marketplace = JSON.parse(await readFile(marketplacePath, "utf8"));
const pluginEntry = marketplace.plugins?.find((candidate) => candidate.name === "cogentstack");

const fail = (message) => {
  throw new Error(`Claude marketplace validation failed: ${message}`);
};

if (marketplace.name !== "cogentstack") fail("marketplace name must be cogentstack");
if (!pluginEntry) fail("cogentstack plugin entry is missing");
if (pluginEntry.source !== "./claude-plugins/cogentstack") fail("plugin source must remain inside the Claude package directory");
if (!/^[0-9]+\.[0-9]+\.[0-9]+$/.test(pluginEntry.version ?? "")) fail("plugin version must use semantic versioning");

const pluginRoot = resolve(repositoryRoot, pluginEntry.source);
if (relative(repositoryRoot, pluginRoot).startsWith("..")) fail("plugin source escapes the repository");

const manifestPath = join(pluginRoot, ".claude-plugin", "plugin.json");
const skillPath = join(pluginRoot, "skills", "cogentstack", "SKILL.md");
const scriptsRoot = join(pluginRoot, "skills", "cogentstack", "scripts");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const skill = await readFile(skillPath, "utf8");

if (manifest.name !== "cogentstack") fail("plugin manifest name must be cogentstack");
if (manifest.version !== pluginEntry.version) fail("marketplace and plugin versions differ");
if (!skill.startsWith("---\nname: cogentstack\n")) fail("skill frontmatter is invalid");
for (const marker of [
  "$cogentstack",
  "${CLAUDE_PLUGIN_ROOT}",
  "surface` is `claude-desktop`",
  "hide-claude-sidebar.ps1",
  "open-cogentstack-panel.ps1",
  "normal Google Chrome or Microsoft Edge window",
  "passive 12-pixel white divider with a two-pixel neutral-grey rule matching the adjacent app border",
  "maximized normal window",
  "fulfil-project.ps1",
  "delete-project.ps1",
  "prepare-deployment.ps1",
  "Do not implement, imply, or silently fall back to a Claude Web connector",
]) {
  if (!skill.includes(marker)) fail(`skill is missing required marker: ${marker}`);
}
for (const forbidden of ["codex_app__open_in_codex", "placement` set to `right", "surface=chatgpt"]) {
  if (skill.includes(forbidden)) fail(`Claude skill contains a Codex-only instruction: ${forbidden}`);
}

const requiredScripts = [
  "connect-cogentstack.ps1",
  "delete-project.ps1",
  "ensure-cogentstack.ps1",
  "fulfil-project.ps1",
  "hide-claude-sidebar.ps1",
  "native-command.ps1",
  "open-cogentstack-panel.ps1",
  "prepare-deployment.ps1",
];
const actualScripts = (await readdir(scriptsRoot)).filter((name) => name.endsWith(".ps1")).sort();
if (JSON.stringify(actualScripts) !== JSON.stringify([...requiredScripts].sort())) {
  fail(`unexpected script inventory: ${actualScripts.join(", ")}`);
}

const deletionSource = await readFile(join(scriptsRoot, "delete-project.ps1"), "utf8");
if (!deletionSource.includes("[string]::Equals($_, '.tmp', [StringComparison]::OrdinalIgnoreCase)")) {
  fail("deletion helper must compare temporary path segments with the .NET ordinal ignore-case API");
}
if (deletionSource.includes("ToLocaleLowerInvariant")) fail("deletion helper contains a JavaScript-only string method");

const deletionFunctionStart = deletionSource.indexOf("function Resolve-ApprovedDeletionTarget(");
const deletionFunctionEnd = deletionSource.indexOf("\nfunction Get-DecodedProcessCommand", deletionFunctionStart);
if (deletionFunctionStart < 0 || deletionFunctionEnd < 0) fail("deletion target validator function could not be isolated");
const deletionRuntimeCheck = spawnSync("powershell.exe", [
  "-NoProfile",
  "-Command",
  `& {
${deletionSource.slice(deletionFunctionStart, deletionFunctionEnd)}
$valid = Resolve-ApprovedDeletionTarget 'C:\\CogentStack\\projects\\sample' 'C:\\CogentStack\\projects' 'sample'
if ($valid -ne 'C:\\CogentStack\\projects\\sample') { throw 'A valid project path was not accepted.' }
try {
  Resolve-ApprovedDeletionTarget 'C:\\CogentStack\\projects\\.TMP' 'C:\\CogentStack\\projects' '.TMP' | Out-Null
  throw 'A temporary project path was accepted.'
} catch {
  if ($_.Exception.Message -ne 'Temporary validation projects cannot be deleted through the project library.') { throw }
}
}`,
], { encoding: "utf8" });
if (deletionRuntimeCheck.status !== 0) {
  fail(`deletion target validator failed at runtime: ${(deletionRuntimeCheck.stderr || deletionRuntimeCheck.stdout).trim()}`);
}

const ensureSource = await readFile(join(scriptsRoot, "ensure-cogentstack.ps1"), "utf8");
if (!ensureSource.includes("https://cogentstack.app/stack?surface=claude-desktop")) fail("readiness helper does not use the Claude Desktop surface");
if (ensureSource.includes("surface=chatgpt")) fail("readiness helper falls back to the ChatGPT surface");

const panelSource = await readFile(join(scriptsRoot, "open-cogentstack-panel.ps1"), "utf8");
for (const marker of [
  "Confirm-CogentStackUrl",
  "Get-CompanionBrowsers",
  "Find-ExistingCogentStackWindow",
  "Set-BrowserPageOnly",
  "Start-WhiteBackdrop",
  "Start-WhiteDivider",
  "CogentStack Claude Workspace Divider",
  "WS_EX_TRANSPARENT",
  "WS_EX_NOACTIVATE",
  "dividerMasksShadows",
  "dividerEdgeVisible",
  "CogentStackPanelEdge",
  "FromArgb(205, 205, 205)",
  "dividerEdgeColor = '#CDCDCD'",
  "GetWindow(IntPtr hWnd, uint command)",
  "IsWindowAbove(IntPtr upper, IntPtr lower)",
  "Test-WorkspacePanelsAboveBackdrop",
  "workspacePanelsAboveBackdrop",
  "$watchLayoutVerified",
  "$watchHeaderVisible",
  "function Test-CogentStackHeaderVisible",
  "function Wait-CogentStackHeaderVisible",
  "$topInset = if ($normalChromeHeight -gt 0)",
  "$top = if ($PreserveOffscreenTop) { 0 } else { $documentTop }",
  "Set-WindowContentRegion $Window $documentFinal $true",
  "$documentTop -lt 0",
  "topCropRemoved = [bool]($clipInsets.top -eq 0)",
  "browserTopCropRemoved = [bool]$pageOnly.topCropRemoved",
  "$layoutAccepted = [bool]($layout.verified -and $layering.verified -and $headerVisible -and $pageOnly.topCropRemoved)",
  "status = 'resume_rejected'",
  "status = 'layout_rejected'",
  "SetWindowPos([IntPtr]$Divider.Handle, [IntPtr]$PanelWindow.Handle",
  "$activeLayout.verified",
  "ShowWindow([IntPtr]$watchDivider.Handle, 0)",
  "$parsed = ConvertTo-CogentStackUri $Address",
  "schemaVersion = 11",
  "Start-CompanionExitWatcher",
  "Test-CompanionOwnedAddress",
  "Test-CompanionSuspendAddress",
  "Test-CompanionResumeAddress",
  "if (Test-CompanionResumeAddress $watchAddress)",
  "if ($layoutStatus -eq 'suspended')",
  "status = 'already_active'",
  "Suspend-CompanionLayout",
  "Resume-CompanionLayout",
  "CogentStack Work Mode (Claude).lnk",
  "$watchAddress -and -not (Test-CompanionOwnedAddress $watchAddress)",
  "Restore-CompanionLayout $watchState $false $true $true",
  "claude-companion-layout.json",
  "opened_unarranged",
  "accountState",
  "layoutVerified",
  "Test-CogentStackTerminalInstallAddress",
  "Remove-TerminalCogentStackInstallationTabs",
  "Select-BrowserTabCandidate $panelSelection",
  "retiredCompletedInstallTabs",
]) {
  if (!panelSource.includes(marker)) fail(`companion helper is missing required marker: ${marker}`);
}
for (const forbidden of ["--app=", "--new-window", "{F11}", "SetParent(", "FindWindow(", "SendKeys", "cogentstack://desktop"]) {
  if (panelSource.includes(forbidden)) fail(`companion helper crosses the supported window boundary: ${forbidden}`);
}
if (panelSource.includes("TopMost = `$true")) fail("Claude divider must not be globally topmost");
const claudeWatchAddressIndex = panelSource.indexOf("$watchAddress = Get-BrowserAddressValue $watchPanel");
const claudeDeletionIndex = panelSource.indexOf("if (Test-CompanionProjectDeletionAddress $watchAddress)", claudeWatchAddressIndex);
const claudeLayoutIndex = panelSource.indexOf("$layoutStatus =", claudeWatchAddressIndex);
if (claudeWatchAddressIndex < 0 || claudeDeletionIndex <= claudeWatchAddressIndex || claudeDeletionIndex >= claudeLayoutIndex) {
  fail("Claude companion must process approved deletion immediately after reading the normalized browser address");
}

const validateExistingTabReuse = (source, label) => {
  for (const marker of [
    "ConvertTo-CogentStackUri",
    "Test-CogentStackHomeAddress",
    "Set-BrowserWorkspaceAddress",
    "Wait-AccountState",
    "CogentStack \\| AI Production Stack",
    "$reusedExistingTab = [bool]$panelSelection",
    "$reusedExistingHomeTab = [bool]$panelSelection.IsHome",
    "$signedInHome",
    "$homeWindow",
    "if (-not $isWorkspace -and -not $isHome -and -not $isTerminalInstall)",
    "if (-not [bool]$panelSelection.IsWorkspace)",
    "reusedExistingHomeTab = $reusedExistingHomeTab",
    "reusedTerminalInstallTab = $reusedTerminalInstallTab",
    "retiredCompletedInstallTabs = $retiredCompletedInstallTabs",
  ]) {
    if (!source.includes(marker)) fail(`${label} helper is missing existing-tab reuse marker: ${marker}`);
  }
  if (source.includes("reusedExistingTab = [bool]$panelSelection.ReusedExistingTab")) {
    fail(`${label} helper still reports a newly opened tab as reused`);
  }
  const selectionIndex = source.indexOf("$panelSelection = Find-ExistingCogentStackWindow");
  const reuseIndex = source.indexOf("if ($panelSelection)", selectionIndex);
  const newTabIndex = source.indexOf("Start-Process -FilePath $preferredBrowser.ExecutablePath", selectionIndex);
  if (selectionIndex < 0 || reuseIndex < selectionIndex || newTabIndex < reuseIndex) {
    fail(`${label} helper must reuse and navigate an existing CogentStack tab before opening a new tab`);
  }
};

validateExistingTabReuse(panelSource, "Claude");
const codexScriptsRoot = join(repositoryRoot, "plugins", "cogentstack", "skills", "cogentstack", "scripts");
const codexCompanionSource = await readFile(join(codexScriptsRoot, "open-cogentstack-companion.ps1"), "utf8");
validateExistingTabReuse(codexCompanionSource, "Codex");
for (const marker of [
  "Test-CompanionOwnedAddress",
  "Test-CompanionSuspendAddress",
  "Test-CompanionResumeAddress",
  "if (Test-CompanionResumeAddress $watchAddress)",
  "if ($layoutStatus -eq 'suspended')",
  "status = 'already_active'",
  "Suspend-CompanionLayout",
  "Resume-CompanionLayout",
  "CogentStack Work Mode (Codex).lnk",
  "Start-WhiteDivider",
  "CogentStack Workspace Divider",
  "WS_EX_TRANSPARENT",
  "WS_EX_NOACTIVATE",
  "dividerMasksShadows",
  "dividerEdgeVisible",
  "CogentStackPanelEdge",
  "FromArgb(205, 205, 205)",
  "dividerEdgeColor = '#CDCDCD'",
  "GetWindow(IntPtr hWnd, uint command)",
  "IsWindowAbove(IntPtr upper, IntPtr lower)",
  "Test-WorkspacePanelsAboveBackdrop",
  "workspacePanelsAboveBackdrop",
  "$watchLayoutVerified",
  "$watchHeaderVisible",
  "function Test-CogentStackHeaderVisible",
  "function Wait-CogentStackHeaderVisible",
  "$topInset = if ($normalChromeHeight -gt 0)",
  "$top = if ($PreserveOffscreenTop) { 0 } else { $documentTop }",
  "Set-WindowContentRegion $Window $documentFinal $true",
  "$documentTop -lt 0",
  "topCropRemoved = [bool]($clipInsets.top -eq 0)",
  "browserTopCropRemoved = [bool]$pageOnly.topCropRemoved",
  "$layoutAccepted = [bool]($layout.verified -and $layering.verified -and $headerVisible -and $pageOnly.topCropRemoved)",
  "status = 'resume_rejected'",
  "status = 'layout_rejected'",
  "SetWindowPos([IntPtr]$Divider.Handle, [IntPtr]$PanelWindow.Handle",
  "$activeLayout.verified",
  "ShowWindow([IntPtr]$watchDivider.Handle, 0)",
  "$parsed = ConvertTo-CogentStackUri $Address",
  "schemaVersion = 11",
  "$watchAddress -and -not (Test-CompanionOwnedAddress $watchAddress)",
  "($Mode -eq 'Close')",
]) {
  if (!codexCompanionSource.includes(marker)) fail(`Codex companion helper is missing navigation recovery marker: ${marker}`);
}
if (codexCompanionSource.includes("TopMost = `$true")) fail("Codex divider must not be globally topmost");
const codexWatchAddressIndex = codexCompanionSource.indexOf("$watchAddress = Get-BrowserAddressValue $watchPanel");
const codexDeletionIndex = codexCompanionSource.indexOf("if (Test-CompanionProjectDeletionAddress $watchAddress)", codexWatchAddressIndex);
const codexLayoutIndex = codexCompanionSource.indexOf("$layoutStatus =", codexWatchAddressIndex);
if (codexWatchAddressIndex < 0 || codexDeletionIndex <= codexWatchAddressIndex || codexDeletionIndex >= codexLayoutIndex) {
  fail("Codex companion must process approved deletion immediately after reading the normalized browser address");
}

const sidebarSource = await readFile(join(scriptsRoot, "hide-claude-sidebar.ps1"), "utf8");
for (const marker of ["Get-Process -Name Claude", "Hide sidebar", "Show sidebar", "already_hidden"]) {
  if (!sidebarSource.includes(marker)) fail(`Claude sidebar helper is missing required marker: ${marker}`);
}

const parityPairs = [
  ["native-command.ps1", []],
  ["connect-cogentstack.ps1", [
    ["claude-desktop-authorization.json", "desktop-authorization.json"],
    ["claude-desktop-credential.json", "desktop-credential.json"],
    ["Claude Code Desktop on Windows", "ChatGPT Desktop on Windows"],
    ["surface=claude-desktop", "surface=chatgpt"],
  ]],
  ["fulfil-project.ps1", [["claude-desktop-credential.json", "desktop-credential.json"]]],
  ["delete-project.ps1", [["claude-desktop-credential.json", "desktop-credential.json"]]],
  ["prepare-deployment.ps1", [["claude-desktop-credential.json", "desktop-credential.json"]]],
];
for (const [name, replacements] of parityPairs) {
  const source = await readFile(join(codexScriptsRoot, name), "utf8");
  let claude = await readFile(join(scriptsRoot, name), "utf8");
  for (const [from, to] of replacements) claude = claude.replaceAll(from, to);
  if (claude.replaceAll("\r\n", "\n").trimEnd() !== source.replaceAll("\r\n", "\n").trimEnd()) {
    fail(`${name} has drifted beyond its deliberate Claude identity changes`);
  }
}

for (const name of requiredScripts) {
  const path = join(scriptsRoot, name);
  const escapedPath = path.replaceAll("'", "''");
  const syntaxCheck = spawnSync("powershell.exe", [
    "-NoProfile",
    "-Command",
    `& { $tokens = $null; $errors = $null; [void][System.Management.Automation.Language.Parser]::ParseFile('${escapedPath}', [ref]$tokens, [ref]$errors); if ($errors.Count -gt 0) { $errors | ForEach-Object { [Console]::Error.WriteLine($_.Message) }; exit 1 } }`,
  ], { encoding: "utf8" });
  if (syntaxCheck.status !== 0) fail(`${name} has invalid PowerShell syntax: ${syntaxCheck.stderr.trim()}`);
}

const inspect = spawnSync("powershell.exe", [
  "-NoProfile",
  "-ExecutionPolicy", "Bypass",
  "-File", join(scriptsRoot, "open-cogentstack-panel.ps1"),
  "-Mode", "Inspect",
], { encoding: "utf8" });
if (inspect.status !== 0) fail(`safe companion inspection failed: ${inspect.stderr.trim()}`);
let inspection;
try { inspection = JSON.parse(inspect.stdout.trim()); } catch { fail("companion inspection did not return compact JSON"); }
if (
  inspection.status !== "inspected" ||
  inspection.platform !== "windows" ||
  typeof inspection.claudeDesktopWindowFound !== "boolean" ||
  typeof inspection.browserAvailable !== "boolean"
) fail("companion inspection returned an unexpected result");

console.log(JSON.stringify({
  status: "valid",
  marketplace: marketplace.name,
  plugin: manifest.name,
  version: manifest.version,
  surface: "claude-code-desktop",
  scripts: actualScripts.length,
  inspection,
}));
