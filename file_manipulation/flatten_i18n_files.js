// flatten translation structures in i18n JSON files
// e.g., { "shopping": { "cart": "value" } } -> { "shopping.cart": "value" }

const fs = require("fs-extra");

const supportedLanguages = [
  "en-PT",
  "bg-BG",
  "cs-CZ",
  "de-DE",
  "en-GB",
  "en-US",
  "es-ES",
  "fr-FR",
  "hu-HU",
  "id-ID",
  "it-IT",
  "ja-JP",
  "ko-KR",
  "nl-NL",
  "no-NO",
  "pl-PL",
  "pt-BR",
  "pt-PT",
  "ro-RO",
  "ru-RU",
  "sk-SK",
  "sv-SE",
  "tr-TR",
  "zh-CN",
];

JSON.flatten = function (data) {
  var result = {};

  function recurse(cur, prop) {
    if (Object(cur) !== cur) {
      result[prop] = cur;
    } else if (Array.isArray(cur)) {
      for (var i = 0, l = cur.length; i < l; i++)
        recurse(cur[i], prop + "[" + i + "]");
      if (l == 0) result[prop] = [];
    } else {
      var isEmpty = true;
      for (var p in cur) {
        isEmpty = false;
        recurse(cur[p], prop ? prop + "." + p : p);
      }
      if (isEmpty && prop) result[prop] = {};
    }
  }
  recurse(data, "");
  return result;
};

function transformFile(lang, output, inFile) {
  const outFile = `./${lang}.out.json`;

  fs.writeJson(outFile, output, (err) => {
    if (err) return console.error(err);
    console.log(`success! ${inFile} -> ${outFile}`);
  });
}

async function transformFiles() {
  for (const lang of supportedLanguages) {
    const inFile = `./${lang}.json`;
    const file = await require(inFile);
    const output = JSON.flatten(file);
    await transformFile(lang, output, inFile);
  }
}

transformFiles();
