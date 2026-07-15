#!/usr/bin/env node

/**
 * gitlab_find_files.js
 * Finds all files with a given name in a GitLab repository, using the
 * Repository Tree API. Defaults to package.json; pass --filename for anything else.
 *
 * Usage:
 *   node gitlab_find_files.js --project-id <id> --token <token> [--filename <name>] [--host <gitlab-host>] [--ref <branch>]
 *
 * Environment variables (alternative to flags):
 *   GITLAB_TOKEN   - your GitLab personal access token
 *   GITLAB_HOST    - GitLab host (default: gitlab.com)
 *   GITLAB_PROJECT - project ID or URL-encoded namespace/project
 */

const args = process.argv.slice(2);

function getArg(flag) {
  const idx = args.indexOf(flag);
  return idx !== -1 ? args[idx + 1] : null;
}

const PROJECT_ID  = getArg("--project-id") || process.env.GITLAB_PROJECT;
const TOKEN       = getArg("--token")      || process.env.GITLAB_TOKEN;
const HOST        = getArg("--host")       || process.env.GITLAB_HOST || "gitlab.com";
const REF         = getArg("--ref")        || "HEAD";
const FILENAME    = getArg("--filename")   || "package.json";

if (!PROJECT_ID || !TOKEN) {
  console.error(`
Usage:
  node find_packages.js --project-id <id> --token <token> [options]

Options:
  --project-id   GitLab project ID or URL-encoded path (required)
  --token        GitLab personal access token (required)
  --host         GitLab host, e.g. gitlab.mycompany.com (default: gitlab.com)
  --ref          Branch, tag, or commit SHA to search (default: HEAD)
  --filename     File name to search for (default: package.json)

Environment variables:
  GITLAB_TOKEN, GITLAB_HOST, GITLAB_PROJECT
  `);
  process.exit(1);
}

const BASE_URL = `https://${HOST}/api/v4/projects/${encodeURIComponent(PROJECT_ID)}`;
const PER_PAGE = 100;

async function fetchPage(page) {
  const url = `${BASE_URL}/repository/tree?recursive=true&per_page=${PER_PAGE}&page=${page}&ref=${REF}`;
  const res = await fetch(url, {
    headers: { "PRIVATE-TOKEN": TOKEN },
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`GitLab API error ${res.status}: ${body}`);
  }

  return res.json();
}

async function findFiles() {
  const matched = [];
  let page = 1;
  let totalFetched = 0;

  console.log(`\n🔍 Searching for "${FILENAME}" in project ${PROJECT_ID} (ref: ${REF})...\n`);

  while (true) {
    let items;

    try {
      items = await fetchPage(page);
    } catch (err) {
      console.error(`❌ Failed on page ${page}: ${err.message}`);
      process.exit(1);
    }

    totalFetched += items.length;

    const hits = items.filter(
      (f) => f.type === "blob" && f.name === FILENAME
    );
    matched.push(...hits);

    process.stdout.write(`   Page ${page}: ${items.length} items fetched, ${hits.length} match(es) found\r`);

    if (items.length < PER_PAGE) break;
    page++;
  }

  return { matched, totalFetched, pages: page };
}

async function main() {
  const { matched, totalFetched, pages } = await findFiles();

  console.log(`\n\n✅ Done — scanned ${totalFetched} files across ${pages} page(s)\n`);

  if (matched.length === 0) {
    console.log(`No "${FILENAME}" files found.`);
    return;
  }

  console.log(`Found ${matched.length} "${FILENAME}" file(s):\n`);
  matched.forEach((f, i) => {
    console.log(`  ${i + 1}. ${f.path}`);
  });

  console.log();
}

main();