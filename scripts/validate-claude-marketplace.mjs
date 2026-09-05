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
  "12-pixel vertical divider",
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
  "Start-CompanionExitWatcher",
  "Restore-CompanionLayout $watchState $false $true $true",
  "claude-companion-layout.json",
  "opened_unarranged",
  "accountState",
  "layoutVerified",
]) {
  if (!panelSource.includes(marker)) fail(`companion helper is missing required marker: ${marker}`);
}
for (const forbidden of ["--app=", "--new-window", "{F11}", "SetParent(", "FindWindow(", "SendKeys", "cogentstack://desktop"]) {
  if (panelSource.includes(forbidden)) fail(`companion helper crosses the supported window boundary: ${forbidden}`);
}

const sidebarSource = await readFile(join(scriptsRoot, "hide-claude-sidebar.ps1"), "utf8");
for (const marker of ["Get-Process -Name Claude", "Hide sidebar", "Show sidebar", "already_hidden"]) {
  if (!sidebarSource.includes(marker)) fail(`Claude sidebar helper is missing required marker: ${marker}`);
}

const codexScriptsRoot = join(repositoryRoot, "plugins", "cogentstack", "skills", "cogentstack", "scripts");
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
