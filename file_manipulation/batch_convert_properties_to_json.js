import { parse } from "properties";
import { join } from "path";
import { homedir } from "os";
import { glob } from "node:fs";
import { outputJsonSync } from "fs-extra";

const directoryPath = join(
  homedir(),
  "src",
  "projectA",
  "backend",
  "src",
  "locales"
);

glob(`${directoryPath}/*.properties`, (_error, matches) => {
  matches.forEach((match) => {
    const jsonFilename = match.replace(".properties", ".json");

    parse(match, { path: true }, (_error, props) => {
      outputJsonSync(jsonFilename, props);
    });
  });
});
