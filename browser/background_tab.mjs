#!/usr/bin/env node
// Checks a page in a background tab of a browser listening on CDP, without
// ever taking focus, so whatever is in front stays in front.
//
//   background_tab.mjs open   <url>              open a tab behind the others
//   background_tab.mjs eval   <match> <js>       evaluate js in the tab, print the result
//   background_tab.mjs listen <match> <seconds>  print its console warnings and errors
//   background_tab.mjs reload <match>            reload it, then print what it logged
//   background_tab.mjs close  <match>            close it
//
// A tab is matched by any part of its URL, since a page may change its
// fragment while it is checked. The port is CDP_PORT, 9222 unless set.

const PORT = process.env.CDP_PORT ?? "9222";
const [verb, target, extra] = process.argv.slice(2);
const USAGE = "usage: background_tab.mjs open <url> | eval <match> <js> | listen <match> <seconds> | reload <match> | close <match>";

if (!verb || !target) fail(USAGE);

function fail(message) {
  console.error(message);
  process.exit(1);
}

async function connect(url) {
  const socket = new WebSocket(url);
  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", () => reject(new Error(`cannot reach ${url}`)), { once: true });
  });
  let next = 0;
  const call = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++next;
      const answer = (event) => {
        const data = JSON.parse(event.data);
        if (data.id !== id) return;
        socket.removeEventListener("message", answer);
        if (data.error) reject(new Error(data.error.message));
        else resolve(data.result);
      };
      socket.addEventListener("message", answer);
      socket.send(JSON.stringify({ id, method, params }));
    });
  return { socket, call };
}

async function browser() {
  const response = await fetch(`http://127.0.0.1:${PORT}/json/version`).catch(() => fail(`nothing listens on CDP port ${PORT}`));
  return connect((await response.json()).webSocketDebuggerUrl);
}

async function tab(match) {
  const tabs = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
  const found = tabs.filter((candidate) => candidate.type === "page" && candidate.url.includes(match));
  if (found.length === 0) fail(`no tab's URL contains ${match}`);
  if (found.length > 1) fail(`several tabs' URLs contain ${match}:\n${found.map((one) => one.url).join("\n")}`);
  return found[0];
}

// Prints what the page logs as a warning or an error, and what it throws.
function logging(socket) {
  socket.addEventListener("message", (event) => {
    const data = JSON.parse(event.data);
    if (data.method === "Runtime.consoleAPICalled" && ["warning", "error"].includes(data.params.type)) {
      console.log(data.params.type, data.params.args.map((arg) => arg.value ?? arg.description).join(" "));
    }
    if (data.method === "Runtime.exceptionThrown") {
      const details = data.params.exceptionDetails;
      console.log("exception", details.exception?.description ?? details.text);
    }
  });
}

const sleep = (seconds) => new Promise((resolve) => setTimeout(resolve, seconds * 1000));

if (verb === "open") {
  const { socket, call } = await browser();
  const { targetId } = await call("Target.createTarget", { url: target, background: true });
  console.log(targetId);
  socket.close();
} else if (verb === "close") {
  const { socket, call } = await browser();
  await call("Target.closeTarget", { targetId: (await tab(target)).id });
  socket.close();
} else if (verb === "eval") {
  if (!extra) fail(USAGE);
  const { socket, call } = await connect((await tab(target)).webSocketDebuggerUrl);
  const { result, exceptionDetails } = await call("Runtime.evaluate", { expression: extra, returnByValue: true, awaitPromise: true });
  console.log(exceptionDetails ? `exception: ${exceptionDetails.exception?.description ?? exceptionDetails.text}` : JSON.stringify(result.value, null, 1));
  socket.close();
} else if (verb === "listen" || verb === "reload") {
  const { socket, call } = await connect((await tab(target)).webSocketDebuggerUrl);
  logging(socket);
  await call("Runtime.enable");
  if (verb === "reload") await call("Page.reload");
  await sleep(verb === "listen" ? Number(extra ?? 10) : 5);
  socket.close();
} else {
  fail(USAGE);
}
