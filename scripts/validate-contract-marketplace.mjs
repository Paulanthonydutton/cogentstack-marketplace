import { lstat, readFile, readdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const registryPath = join(repositoryRoot, "contracts", "marketplace.json");
const forbiddenExtensions = new Set([".bat", ".bin", ".cjs", ".cmd", ".com", ".dll", ".exe", ".js", ".mjs", ".msi", ".ps1", ".sh", ".ts", ".tsx"]);
const semver = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?$/;
const packId = /^[a-z0-9]+(?:[.-][a-z0-9]+)*$/;
const itemId = /^[a-z][a-z0-9-]{2,79}$/;

function fail(message) {
  throw new Error(`Contract marketplace validation failed: ${message}`);
}

async function json(path) {
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch (error) {
    fail(`${path} is not valid JSON (${error instanceof Error ? error.message : String(error)})`);
  }
}

function unique(items, label) {
  if (new Set(items).size !== items.length) fail(`${label} contains duplicate IDs`);
}

function validateEvidence(evidence, label) {
  const allowed = new Set(["artifact", "configuration", "review-record", "static-analysis", "test-output"]);
  if (!Array.isArray(evidence) || evidence.length === 0 || evidence.some((value) => !allowed.has(value))) {
    fail(`${label} must declare recognised evidence`);
  }
}

function validatePack(pack, location) {
  if (pack.protocolVersion !== "0.1" || pack.kind !== "guardrail-pack") fail(`${location} uses an unsupported protocol`);
  if (!packId.test(pack.id ?? "")) fail(`${location} has an invalid pack ID`);
  if (!semver.test(pack.version ?? "")) fail(`${location} has an invalid semantic version`);
  if (pack.execution?.mode !== "declarative" || pack.execution?.allowScripts !== false) fail(`${location} must prohibit scripts`);
  if (!Array.isArray(pack.projectTypes) || pack.projectTypes.length === 0) fail(`${location} must identify at least one project type`);
  for (const collection of ["requirements", "controls", "acceptance"]) {
    if (!Array.isArray(pack[collection]) || pack[collection].length === 0) fail(`${location} must contain ${collection}`);
    unique(pack[collection].map((item) => item.id), `${location} ${collection}`);
    if (pack[collection].some((item) => !itemId.test(item.id ?? ""))) fail(`${location} has an invalid ${collection} ID`);
  }
  for (const requirement of pack.requirements) validateEvidence(requirement.evidence, `${location} requirement ${requirement.id}`);
  for (const criterion of pack.acceptance) validateEvidence(criterion.evidence, `${location} acceptance ${criterion.id}`);
  if (!Array.isArray(pack.guidance) || pack.guidance.length === 0) fail(`${location} must contain guidance`);
}

async function rejectExecutableContent(root, current = root) {
  for (const entry of await readdir(current, { withFileTypes: true })) {
    const path = join(current, entry.name);
    const status = await lstat(path);
    if (status.isSymbolicLink()) fail(`${path} is a symbolic link`);
    if (entry.isDirectory()) await rejectExecutableContent(root, path);
    if (entry.isFile()) {
      const extension = entry.name.includes(".") ? `.${entry.name.split(".").pop().toLowerCase()}` : "";
      if (forbiddenExtensions.has(extension)) fail(`${path} is executable content and is not permitted`);
    }
  }
}

const registry = await json(registryPath);
if (registry.protocolVersion !== "0.1" || !Array.isArray(registry.entries)) fail("registry protocol is unsupported");
unique(registry.entries.map((entry) => `${entry.id}@${entry.version}`), "registry");

for (const entry of registry.entries) {
  if (!packId.test(entry.id ?? "") || !semver.test(entry.version ?? "")) fail("registry contains an invalid identity");
  if (!new Set(["example", "community", "verified", "official"]).has(entry.trustLevel)) fail(`${entry.id} has an invalid trust level`);
  if (entry.status !== "example" && !/^[a-f0-9]{40}$/.test(entry.source?.revision ?? "")) fail(`${entry.id} must pin a 40-character Git revision`);
  if (entry.status !== "example" && !/^[a-f0-9]{64}$/.test(entry.source?.sha256 ?? "")) fail(`${entry.id} must pin a SHA-256 digest`);
  if (entry.status === "example") {
    const root = resolve(repositoryRoot, entry.source.path);
    const manifest = await json(join(root, "guardrail-pack.json"));
    validatePack(manifest, entry.source.path);
    if (manifest.id !== entry.id || manifest.version !== entry.version) fail(`${entry.id} does not match its registry identity`);
    await rejectExecutableContent(root);
  }
}

console.log(JSON.stringify({ status: "valid", protocolVersion: registry.protocolVersion, entries: registry.entries.length }));

