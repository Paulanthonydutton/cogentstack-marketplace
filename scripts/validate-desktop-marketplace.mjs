import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const manifestPath = join(repositoryRoot, "desktop", "marketplace.json");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const semver = /^[0-9]+\.[0-9]+\.[0-9]+$/;
const sha256 = /^[a-f0-9]{64}$/;

const fail = (message) => {
  throw new Error(`Desktop marketplace validation failed: ${message}`);
};

if (manifest.schemaVersion !== 1) fail("schemaVersion must be 1");
if (manifest.application !== "CogentStack Desktop") fail("application identity is invalid");
if (!semver.test(manifest.latestVersion ?? "")) fail("latestVersion must be semantic versioning");
if (!semver.test(manifest.minimumSupportedVersion ?? "")) fail("minimumSupportedVersion must be semantic versioning");

const expectedTag = `desktop-v${manifest.latestVersion}`;
if (manifest.releaseTag !== expectedTag) fail(`releaseTag must be ${expectedTag}`);
if (manifest.releasePageUrl !== `https://github.com/Paulanthonydutton/cogentstack-marketplace/releases/tag/${expectedTag}`) {
  fail("releasePageUrl must use the CogentStack Git marketplace release");
}
if (!Array.isArray(manifest.releaseNotes) || manifest.releaseNotes.length === 0 || manifest.releaseNotes.some((note) => typeof note !== "string" || !note.trim() || note.length > 240)) {
  fail("releaseNotes must contain concise non-empty entries");
}

const windows = manifest.windows ?? {};
const expectedFilename = `CogentStack-Desktop-${manifest.latestVersion}-x64-setup.exe`;
const expectedInstallerUrl = `https://github.com/Paulanthonydutton/cogentstack-marketplace/releases/download/${expectedTag}/${expectedFilename}`;
if (windows.architecture !== "x64") fail("the first Windows release must target x64");
if (windows.installerUrl !== expectedInstallerUrl) fail("installerUrl must be the versioned GitHub Release asset");
if (!sha256.test(windows.installerSha256 ?? "")) fail("installerSha256 must be a lowercase SHA-256 digest");
if (!Number.isSafeInteger(windows.installerSizeBytes) || windows.installerSizeBytes < 1) fail("installerSizeBytes must be a positive integer");
if (typeof windows.authenticodeSigned !== "boolean") fail("authenticodeSigned must be explicit");
if (windows.requiresUserApproval !== true) fail("Windows installation must retain user approval");
if (windows.automaticLaunch !== false) fail("first installation must not claim to launch automatically");

console.log(JSON.stringify({
  status: "valid",
  application: manifest.application,
  version: manifest.latestVersion,
  tag: manifest.releaseTag,
  installer: expectedFilename,
  sha256: windows.installerSha256,
  size: windows.installerSizeBytes,
  automaticLaunch: windows.automaticLaunch,
}));
