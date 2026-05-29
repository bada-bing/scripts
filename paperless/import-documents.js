#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import correspondents from "./correspondents.json" with { type: "json" };

const PAPERLESS_URL = process.env.PAPERLESS_URL;
const PAPERLESS_TOKEN = process.env.PAPERLESS_TOKEN;

if (!PAPERLESS_URL || !PAPERLESS_TOKEN) {
  console.error("Missing PAPERLESS_URL or PAPERLESS_TOKEN");
  process.exit(1);
}

const files = process.argv.slice(2);

if (files.length === 0) {
  console.error("Usage: ./import-paperless.js inbox/*.pdf");
  process.exit(1);
}

function extractCorrespondent(filename) {
  const base = path.basename(filename);
  const match = base.match(/^\d{4}_\d{2}-([^-]+)-/);

  if (!match) {
    throw new Error(`Cannot extract correspondent from: ${base}`);
  }

  return normalizeCorrespondent(match[1]);
}

function normalizeCorrespondent(raw) {
  const found = correspondents.find(
    (c) => c.abbreviation === raw
  );

  if (found) {
    return found.name;
  }

  return raw
    .toLowerCase()
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

async function paperless(pathname, options = {}) {
  const res = await fetch(`${PAPERLESS_URL}${pathname}`, {
    ...options,
    headers: {
      Authorization: `Token ${PAPERLESS_TOKEN}`,
      ...(options.headers ?? {}),
    },
  });

  if (!res.ok) {
    throw new Error(`${res.status} ${res.statusText}: ${await res.text()}`);
  }

  return res.json();
}

async function findOrCreateCorrespondent(name) {
  const result = await paperless(
    `/api/correspondents/?query=${encodeURIComponent(name)}`
  );

  const existing = result.results?.find((c) => c.name === name);
  if (existing) return existing.id;

  const created = await paperless("/api/correspondents/", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ name }),
  });

  return created.id;
}

async function uploadDocument(file, correspondentId) {
  const data = new FormData();
  const buffer = await fs.readFile(file);
  const blob = new Blob([buffer]);

  data.append("document", blob, path.basename(file));
  data.append("correspondent", String(correspondentId));

  return paperless("/api/documents/post_document/", {
    method: "POST",
    body: data,
  });
}

for (const file of files) {
  try {
    const correspondent = extractCorrespondent(file);
    const correspondentId = await findOrCreateCorrespondent(correspondent);

    console.log(`Importing ${file}`);
    console.log(`  correspondent: ${correspondent}`);

    await uploadDocument(file, correspondentId);

    console.log("  done");
  } catch (error) {
    console.error(`Failed: ${file}`);
    console.error(`  ${error.message}`);
  }
}